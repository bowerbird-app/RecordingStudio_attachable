# frozen_string_literal: true

module RecordingStudioAttachable
  class AttachmentUploadsController < ApplicationController
    def new
      @recording = find_recording
      capability_options = capability_options_for(@recording)
      @upload_redirect_params = attachment_redirect_params(fallback_return_to: request.referer)

      authorize_attachment_action!(:upload, @recording, capability_options: capability_options)
      @allowed_content_types = configured_attachable_option(@recording, :allowed_content_types)
      @max_file_size = configured_attachable_option(@recording, :max_file_size)
      @max_file_count = configured_attachable_option(@recording, :max_file_count)
      @image_processing_enabled = configured_attachable_option(@recording, :image_processing_enabled)
      @image_processing_max_width = configured_attachable_option(@recording, :image_processing_max_width)
      @image_processing_max_height = configured_attachable_option(@recording, :image_processing_max_height)
      @image_processing_quality = configured_attachable_option(@recording, :image_processing_quality)
      @upload_providers = configured_upload_providers(@recording)
      @create_path = recording_attachments_path(@recording, @upload_redirect_params)
    end

    def create
      @recording = find_recording
      capability_options = capability_options_for(@recording)

      authorize_attachment_action!(:upload, @recording, capability_options: capability_options)
      result = RecordingStudioAttachable::Services::RecordAttachmentUploads.call(
        parent_recording: @recording,
        actor: current_attachable_actor,
        impersonator: current_attachable_impersonator,
        attachments: attachment_payloads
      )

      respond_to do |format|
        format.html do
          if result.success?
            redirect_to resolved_attachment_redirect_path(@recording), notice: "Uploaded #{result.value.size} attachment(s)."
          else
            redirect_to recording_attachment_upload_path(@recording, attachment_redirect_params), alert: result.error
          end
        end
        format.json do
          if result.success?
            render json: {
              attachments: Array(result.value).map { |recording| attachment_json(recording) },
              redirect_path: resolved_attachment_redirect_path(@recording)
            }, status: :created
          else
            render json: { error: result.error, errors: result.errors }, status: :unprocessable_content
          end
        end
      end
    end

    private

    def attachment_payloads
      permitted = params.permit(attachments: %i[signed_blob_id name description])

      Array(permitted.fetch(:attachments, [])).map do |attachment|
        attachment.to_h.symbolize_keys
      end
    end

    def attachment_json(recording)
      attachment = recording.recordable

      {
        id: recording.id,
        name: attachment.name,
        description: attachment.description,
        content_type: attachment.content_type,
        byte_size: attachment.byte_size,
        attachment_kind: attachment.attachment_kind,
        thumbnail_url: authorized_attachment_preview_path(recording, :square_small) || authorized_attachment_file_path(recording),
        insert_url: authorized_attachment_file_path(recording),
        alt: attachment.name,
        show_path: attachment_path(recording)
      }
    end
  end
end
