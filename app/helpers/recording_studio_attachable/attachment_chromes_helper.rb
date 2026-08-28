# frozen_string_literal: true

require "recording_studio_attachable/attachment_chrome"

module RecordingStudioAttachable
  module AttachmentChromesHelper
    def attachment_chrome_frame_dom_id(recording, kind:)
      AttachmentChrome.frame_dom_id(recording, kind:)
    end

    def render_attachment_file_button(recording, return_to:)
      render_attachment_chrome_frame(
        recording,
        return_to:,
        identity: AttachmentChrome.identity_for(kind: AttachmentChrome::KIND_FILE_BUTTON)
      )
    end

    def render_attachment_image_slot(recording, return_to:, shape: AttachmentChrome::DEFAULT_SHAPE,
                                     size: AttachmentChrome::DEFAULT_SIZE)
      render_attachment_chrome_frame(
        recording,
        return_to:,
        identity: AttachmentChrome.identity_for(
          kind: AttachmentChrome::KIND_IMAGE_SLOT,
          shape: shape,
          size: size
        )
      )
    end

    def attachment_chrome_locals(recording:, return_to:, identity:)
      AttachmentChrome.locals(recording:, return_to:, identity:)
    end

    def attachment_chrome_redirect_params(return_to:)
      AttachmentChrome.redirect_params(return_to:)
    end

    def attachment_chrome_accept_attribute(allowed_content_types)
      AttachmentChrome.accept_attribute(allowed_content_types)
    end

    private

    def render_attachment_chrome_frame(recording, return_to:, identity:)
      render partial: "recording_studio_attachable/attachment_chromes/frame",
             locals: {
               recording: recording,
               return_to: return_to,
               kind: identity.fetch(:kind),
               shape: identity.fetch(:shape),
               size: identity.fetch(:size),
               add_label: identity.fetch(:add_label),
               change_label: identity.fetch(:change_label)
             }
    end
  end
end
