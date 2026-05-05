# frozen_string_literal: true

module RecordingStudioAttachable
  class AttachmentsController < ApplicationController
    def show
      @attachment_recording = find_attachment_recording
      authorize_attachment_owner_action!(:view, @attachment_recording)

      @attachment = @attachment_recording.recordable
      @replace_allowed_content_types = configured_attachable_option(@attachment_recording, :allowed_content_types)
      @replace_max_file_size = configured_attachable_option(@attachment_recording, :max_file_size)
      @owner_recording = attachable_owner_recording(@attachment_recording)
    end

    def update
      @attachment_recording = find_attachment_recording
      authorize_attachment_owner_action!(:revise, @attachment_recording)

      result = if attachment_params[:signed_blob_id].present?
                 RecordingStudioAttachable::Services::ReplaceAttachmentFile.call(
                   attachment_recording: @attachment_recording,
                   actor: current_attachable_actor,
                   impersonator: current_attachable_impersonator,
                   signed_blob_id: attachment_params[:signed_blob_id],
                   name: attachment_params[:name],
                   description: attachment_params[:description]
                 )
               else
                 RecordingStudioAttachable::Services::ReviseAttachmentMetadata.call(
                   attachment_recording: @attachment_recording,
                   actor: current_attachable_actor,
                   impersonator: current_attachable_impersonator,
                   name: attachment_params[:name],
                   description: attachment_params[:description]
                 )
               end

      if result.success?
        redirect_to attachment_path(result.value), notice: "Attachment updated."
      else
        redirect_to attachment_path(@attachment_recording), alert: result.error
      end
    end

    def download
      @attachment_recording = find_attachment_recording
      authorize_attachment_owner_action!(:download, @attachment_recording)

      redirect_to main_app.rails_blob_path(@attachment_recording.recordable.file, disposition: :attachment)
    end

    private

    def attachment_params
      params.require(:attachment).permit(:name, :description, :signed_blob_id)
    end
  end
end
