# frozen_string_literal: true

module RecordingStudioAttachable
  module PreviewProcessorHandling
    SAFE_INLINE_IMAGE_TYPES = %w[
      image/avif
      image/bmp
      image/gif
      image/jpeg
      image/png
      image/tiff
      image/vnd.adobe.photoshop
      image/vnd.microsoft.icon
      image/webp
    ].freeze

    private

    def process_preview(preview_target)
      preview_target.processed
    rescue LoadError, StandardError => e
      raise unless RecordingStudioAttachable::ImageProcessorDiagnostics.processor_unavailable_error?(e)

      handle_unavailable_image_processor(e)
    end

    def safe_inline_content_type?(content_type)
      SAFE_INLINE_IMAGE_TYPES.include?(content_type) &&
        !Array(ActiveStorage.content_types_to_serve_as_binary).include?(content_type)
    end

    def handle_unavailable_image_processor(error)
      logger.error(
        "RecordingStudioAttachable preview processor unavailable " \
        "attachment_recording_id=#{@attachment_recording.id} variant=#{params[:variant_name]} " \
        "#{error.class}: #{error.message}\n#{Array(error.backtrace).join("\n")}"
      )

      render plain: "Image preview is temporarily unavailable", status: :service_unavailable
    end
  end
end
