# frozen_string_literal: true

require_relative "image_header"

module RecordingStudioAttachable
  # Width and height for a blob. PNG, GIF, and JPEG sizes come from the
  # container header, so those files are not opened in vips. Metadata is used
  # only after analysis. Vips is the fallback for a format this header reader
  # does not know, and it reads the header with sequential access.
  module ImageSize
    HEADER_BYTES = 1_048_576

    module_function

    def for(blob)
      from_container(blob) || from_metadata(blob) || from_vips(blob)
    end

    def from_metadata(blob)
      meta = analyzed_metadata(blob)
      return unless meta

      ImageHeader.pair(meta["width"] || meta[:width], meta["height"] || meta[:height])
    rescue StandardError
      nil
    end

    def analyzed_metadata(blob)
      return unless blob.respond_to?(:metadata)
      return if blob.respond_to?(:analyzed?) && !blob.analyzed?

      meta = blob.metadata
      meta if meta.respond_to?(:[])
    end

    def from_vips(blob)
      library = vips_library
      return unless library && blob.respond_to?(:open)

      blob.open { |file| vips_size(library, file) }
    rescue StandardError
      nil
    end

    def from_container(blob)
      ImageHeader.dimensions(header_bytes(blob))
    end

    def vips_size(library, file)
      return unless file.respond_to?(:path) && file.path.present?

      image = library::Image.new_from_file(file.path, access: :sequential)
      ImageHeader.pair(image.width, image.height)
    end

    def header_bytes(blob)
      return unless blob.respond_to?(:open)

      blob.open { |io| io.read(HEADER_BYTES) }
    rescue StandardError
      nil
    end

    def vips_library
      require "vips"
      Vips
    rescue LoadError
      nil
    end
  end
end
