# frozen_string_literal: true

require "base64"
require "tempfile"
require "recording_studio_attachable/image_processor_error_classifier"
require "recording_studio_attachable/image_processor_diagnostics/result"

module RecordingStudioAttachable
  class ImageProcessorDiagnostics
    TRANSFORMATIONS = { resize_to_limit: [1, 1] }.freeze
    TEST_IMAGE = Base64.strict_decode64(
      "iVBORw0KGgoAAAANSUhEUgAAAAIAAAACCAIAAAD91JpzAAAAFElEQVR4nGP8z8DAwMDAxMDAwMDAAAANHQEDasKb6QAAAABJRU5ErkJggg=="
    ).freeze

    class TransformerUnavailable < StandardError; end

    extend ImageProcessorErrorClassifier

    def self.call
      new.call
    end

    def call
      return failure(nil, :active_storage, "Active Storage is not loaded") unless defined?(ActiveStorage)

      processor = configured_processor
      return failure(processor, :unsupported, "unsupported Active Storage variant processor") unless supported?(processor)

      run_diagnostic(processor)
    end

    private

    def run_diagnostic(processor)
      stage = :integration
      load_integration!(processor)
      stage = :transformer
      transformer = build_transformer(processor)
      stage = :transformation
      transform_image(transformer)
      Result.new(success: true, processor: processor)
    rescue LoadError, StandardError => e
      failure_from_error(processor, stage, e)
    end

    def configured_processor
      ActiveStorage.variant_processor
    end

    def supported?(processor)
      %i[vips mini_magick].include?(processor)
    end

    def load_integration!(processor)
      require "active_storage/transformers/image_processing_transformer"
      require processor == :vips ? "image_processing/vips" : "image_processing/mini_magick"
      require processor == :vips ? "active_storage/transformers/vips" : "active_storage/transformers/image_magick"
    end

    def build_transformer(processor)
      transformer_class = ActiveStorage.variant_transformer
      raise TransformerUnavailable, "Active Storage variant transformer is not configured" if transformer_class.nil?

      transformer_class.new(TRANSFORMATIONS)
    rescue TransformerUnavailable
      raise
    rescue StandardError => e
      raise TransformerUnavailable, "#{processor} transformer construction failed: #{e.message}"
    end

    def transform_image(transformer)
      input = Tempfile.new(["recording-studio-attachable-diagnostic", ".png"])
      input.binmode
      input.write(TEST_IMAGE)
      input.rewind

      transformer.transform(input, format: :png) do |output|
        raise "image processor returned an empty result" unless output.size.positive?
      end
    ensure
      input&.close!
    end

    def failure(processor, stage, reason)
      Result.new(
        success: false,
        processor: processor,
        error: reason,
        installation_help: InstallationHelp.new(processor, reason).call,
        stage: stage
      )
    end

    def failure_from_error(processor, stage, error)
      stage = :native_dependency if self.class.native_dependency_error?(error)
      failure(processor, stage, reason_for(processor, stage, error))
    end

    def reason_for(processor, stage, error)
      detail = error.message.to_s.gsub(/\s+/, " ").strip
      "#{reason_prefix(processor, stage)}: #{detail}"
    end

    def reason_prefix(processor, stage)
      case processor
      when :vips, :mini_magick
        supported_reason_prefix(processor, stage)
      else
        "unsupported Active Storage variant processor"
      end
    end

    def supported_reason_prefix(processor, stage)
      {
        integration: "#{processor} Ruby integration could not be loaded",
        native_dependency: "native #{processor == :mini_magick ? 'ImageMagick' : 'libvips'} could not be loaded",
        transformer: "Active Storage could not construct a #{processor} transformer",
        transformation: "#{processor} image transformation failed"
      }.fetch(stage)
    end
  end
end
