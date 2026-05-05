# frozen_string_literal: true

module RecordingStudioAttachable
  class AttachmentUploadsController < ApplicationController
    def new
      @recording = find_recording
      capability_options = capability_options_for(@recording)

      authorize_attachment_action!(:upload, @recording, capability_options: capability_options)
      @allowed_content_types = configured_attachable_option(@recording, :allowed_content_types)
      @max_file_size = configured_attachable_option(@recording, :max_file_size)
      @max_file_count = configured_attachable_option(@recording, :max_file_count)
      @create_path = recording_attachments_path(@recording)
    end

    def create
      @recording = find_recording
      capability_options = capability_options_for(@recording)

      authorize_attachment_action!(:upload, @recording, capability_options: capability_options)
      result = RecordingStudioAttachable::Services::RecordAttachmentUploads.call(
        parent_recording: @recording,
        actor: current_attachable_actor,
        attachments: attachment_payloads
      )

      respond_to do |format|
        format.html do
          if result.success?
            redirect_to recording_attachments_path(@recording), notice: "Uploaded #{result.value.size} attachment(s)."
          else
            redirect_to recording_attachment_upload_path(@recording), alert: result.error
          end
        end
        format.json do
          if result.success?
            render json: {
              attachments: Array(result.value).map { |recording| attachment_json(recording) },
              redirect_path: recording_attachments_path(@recording)
            }, status: :created
          else
            render json: { error: result.error, errors: result.errors }, status: :unprocessable_entity
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
      {
        id: recording.id,
        name: recording.recordable.name,
        content_type: recording.recordable.content_type,
        byte_size: recording.recordable.byte_size,
        attachment_kind: recording.recordable.attachment_kind,
        show_path: attachment_path(recording)
      }
    end
  end
end
