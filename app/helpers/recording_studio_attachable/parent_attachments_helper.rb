# frozen_string_literal: true

require "recording_studio_attachable/parent_attachment_slot"

module RecordingStudioAttachable
  module ParentAttachmentsHelper
    def parent_attachment_frame_dom_id(recording)
      ParentAttachmentSlot.frame_dom_id(recording)
    end

    def render_parent_attachment(recording, return_to:, shape: ParentAttachmentSlot::DEFAULT_SHAPE, size: ParentAttachmentSlot::DEFAULT_SIZE)
      render partial: "recording_studio_attachable/parent_attachments/frame",
             locals: { recording: recording, return_to: return_to, shape: shape, size: size }
    end

    def parent_attachment_slot_locals(recording:, return_to:, shape: ParentAttachmentSlot::DEFAULT_SHAPE, size: ParentAttachmentSlot::DEFAULT_SIZE)
      ParentAttachmentSlot.locals(recording:, return_to:, shape:, size:)
    end

    def parent_attachment_redirect_params(return_to:)
      ParentAttachmentSlot.redirect_params(return_to:)
    end

    def parent_attachment_accept_attribute(allowed_content_types)
      ParentAttachmentSlot.accept_attribute(allowed_content_types)
    end
  end
end
