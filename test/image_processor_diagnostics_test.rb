# frozen_string_literal: true

require "test_helper"

class ImageProcessorDiagnosticsTest < Minitest::Test
  FakeTransformer = Class.new do
    class << self
      attr_accessor :input_path
    end

    def initialize(_transformations); end

    def transform(input, format:)
      self.class.input_path = input.path
      output = Tempfile.new(["diagnostic-output", ".#{format}"])
      output.write("transformed")
      output.rewind
      yield output
    ensure
      output&.close!
    end
  end

  def test_vips_available
    result = call_with(processor: :vips, transformer: FakeTransformer)

    assert result.success?
    assert_equal :vips, result.processor
    assert_nil result.error
  end

  def test_mini_magick_available
    result = call_with(processor: :mini_magick, transformer: FakeTransformer)

    assert result.success?
    assert_equal :mini_magick, result.processor
  end

  def test_vips_native_dependency_unavailable
    result = call_with(processor: :vips, transformer: FakeTransformer) do
      raise LoadError, "Could not open library 'vips.so.42'"
    end

    assert_not result.success?
    assert_equal :native_dependency, result.stage
    assert_includes result.error, "native libvips could not be loaded"
    assert_includes result.installation_help, "apt-get install libvips-tools"
    assert_includes result.installation_help, "brew install vips"
    assert_includes result.installation_help, "apk add vips"
  end

  def test_mini_magick_native_dependency_unavailable
    failing_transformer = Class.new(FakeTransformer) do
      def transform(*)
        raise "ImageMagick executable not found"
      end
    end

    result = call_with(processor: :mini_magick, transformer: failing_transformer)

    assert_not result.success?
    assert_equal :native_dependency, result.stage
    assert_includes result.installation_help, "apt-get install imagemagick"
  end

  def test_unsupported_processor
    result = call_with(processor: :custom, transformer: FakeTransformer)

    assert_not result.success?
    assert_equal :unsupported, result.stage
    assert_includes result.error, "unsupported"
    assert_includes result.installation_help, "Configured processor: custom"
  end

  def test_transformer_construction_failure
    transformer = Class.new do
      def initialize(*)
        raise "constructor failed"
      end
    end

    result = call_with(processor: :vips, transformer: transformer)

    assert_not result.success?
    assert_equal :transformer, result.stage
    assert_includes result.error, "could not construct"
  end

  def test_transformation_failure
    transformer = Class.new(FakeTransformer) do
      def transform(*)
        raise "invalid output"
      end
    end

    result = call_with(processor: :vips, transformer: transformer)

    assert_not result.success?
    assert_equal :transformation, result.stage
    assert_includes result.error, "image transformation failed"
  end

  def test_input_temporary_file_is_cleaned_up
    result = call_with(processor: :vips, transformer: FakeTransformer)

    assert result.success?
    assert_not File.exist?(FakeTransformer.input_path)
  end

  def test_installation_help_includes_rerun_command
    result = call_with(processor: :vips, transformer: nil)

    assert_not result.success?
    assert_includes result.installation_help, "bin/rails generate recording_studio_attachable:install"
  end

  def test_missing_active_storage_returns_structured_failure
    hidden = Object.send(:remove_const, :ActiveStorage)

    result = RecordingStudioAttachable::ImageProcessorDiagnostics.call

    assert_not result.success?
    assert_equal :active_storage, result.stage
    assert_includes result.error, "Active Storage is not loaded"
  ensure
    Object.const_set(:ActiveStorage, hidden) if hidden
  end

  private

  def call_with(processor:, transformer:, &integration_loader)
    diagnostic = RecordingStudioAttachable::ImageProcessorDiagnostics.new
    integration_loader ||= ->(_processor) {}

    ActiveStorage.stub(:variant_processor, processor) do
      ActiveStorage.stub(:variant_transformer, transformer) do
        diagnostic.stub(:load_integration!, integration_loader) { diagnostic.call }
      end
    end
  end
end
