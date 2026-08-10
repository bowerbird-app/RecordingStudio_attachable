# frozen_string_literal: true

require "base64"
require "tempfile"

module RecordingStudioAttachable
  class ImageProcessorDiagnostics
    TRANSFORMATIONS = { resize_to_limit: [1, 1] }.freeze
    TEST_IMAGE = Base64.strict_decode64(
      "iVBORw0KGgoAAAANSUhEUgAAAAIAAAACCAIAAAD91JpzAAAAFElEQVR4nGP8z8DAwMDAxMDAwMDAAAANHQEDasKb6QAAAABJRU5ErkJggg=="
    ).freeze

    class Result
      attr_reader :processor, :error, :installation_help, :stage

      def initialize(success:, processor:, error: nil, installation_help: nil, stage: nil)
        @success = success
        @processor = processor
        @error = error
        @installation_help = installation_help
        @stage = stage
      end

      def success?
        @success
      end
    end

    class TransformerUnavailable < StandardError; end

    class << self
      def call
        new.call
      end

      def processor_unavailable_error?(error)
        return true if error.is_a?(LoadError)
        return true if nil_transformer_error?(error)

        native_dependency_error?(error)
      end

      def native_dependency_error?(error)
        error_message(error).match?(
          /(?:libvips|vips\.(?:so|dylib)|imagemagick|graphicsmagick|magick command|convert command|executable.*not found)/i
        )
      end

      private

      def nil_transformer_error?(error)
        error.is_a?(NoMethodError) &&
          error.respond_to?(:name) &&
          error.name == :new &&
          defined?(ActiveStorage) &&
          ActiveStorage.variant_transformer.nil?
      end

      def error_message(error)
        [error.class.name, error.message].compact.join(": ")
      end
    end

    def call
      processor = configured_processor
      return failure(processor, :unsupported, "unsupported Active Storage variant processor") unless supported?(processor)

      stage = :integration
      load_integration!(processor)

      stage = :transformer
      transformer = build_transformer(processor)

      stage = :transformation
      transform_image(transformer)

      Result.new(success: true, processor: processor)
    rescue LoadError, StandardError => error
      stage = :native_dependency if self.class.native_dependency_error?(error)
      failure(processor, stage, reason_for(processor, stage, error))
    end

    private

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
    rescue StandardError => error
      raise TransformerUnavailable, "#{processor} transformer construction failed: #{error.message}"
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
        installation_help: installation_help(processor, reason),
        stage: stage
      )
    end

    def reason_for(processor, stage, error)
      detail = error.message.to_s.gsub(/\s+/, " ").strip

      case stage
      when :integration
        "#{processor} Ruby integration could not be loaded: #{detail}"
      when :native_dependency
        "native #{native_processor_name(processor)} could not be loaded: #{detail}"
      when :transformer
        "Active Storage could not construct a #{processor} transformer: #{detail}"
      else
        "#{processor} image transformation failed: #{detail}"
      end
    end

    def installation_help(processor, reason)
      <<~HELP
        RecordingStudioAttachable could not use the configured Active Storage
        image processor.

        Configured processor: #{processor || "not configured"}
        Reason: #{reason}

        #{installation_instructions(processor)}

        Then rerun:

          bin/rails generate recording_studio_attachable:install
      HELP
    end

    def installation_instructions(processor)
      case processor
      when :vips
        <<~HELP.chomp
          Install the Ruby integration (`gem "image_processing"`) and libvips:

            Debian/Ubuntu: apt-get install libvips-tools
            macOS:         brew install vips
            Alpine:        apk add vips
        HELP
      when :mini_magick
        <<~HELP.chomp
          Install the Ruby integration (`gem "image_processing"`) and ImageMagick:

            Debian/Ubuntu: apt-get install imagemagick
            macOS:         brew install imagemagick
            Alpine:        apk add imagemagick
        HELP
      else
        <<~HELP.chomp
          Configure `config.active_storage.variant_processor` as `:vips` or `:mini_magick`,
          then install its Ruby integration and native image-processing library.
        HELP
      end
    end

    def native_processor_name(processor)
      processor == :mini_magick ? "ImageMagick" : "libvips"
    end
  end
end
