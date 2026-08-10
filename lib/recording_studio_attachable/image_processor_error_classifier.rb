# frozen_string_literal: true

module RecordingStudioAttachable
  module ImageProcessorErrorClassifier
    def processor_unavailable_error?(error)
      return true if nil_transformer_error?(error)

      integration_load_error?(error) || native_dependency_error?(error)
    end

    def native_dependency_error?(error)
      error_message(error).match?(
        /(?:libvips|vips\.(?:so|dylib)|imagemagick|graphicsmagick|magick command|convert command|executable.*not found)/i
      )
    end

    private

    def integration_load_error?(error)
      error.is_a?(LoadError) &&
        error.message.match?(/(?:image_processing|ruby-vips|vips|mini_magick)/)
    end

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
end
