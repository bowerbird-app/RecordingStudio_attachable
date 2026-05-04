# frozen_string_literal: true

module RecordingStudioAttachable
  class AttachmentsController < ApplicationController
    def show
      @attachment_recording = find_attachment_recording
      authorize_attachment_action!(:view, @attachment_recording.parent_recording || @attachment_recording,
                                   capability_options: capability_options_for(@attachment_recording))
      @attachment = @attachment_recording.recordable
    end

    def update
      @attachment_recording = find_attachment_recording
      authorize_attachment_action!(:revise, @attachment_recording.parent_recording || @attachment_recording,
                                   capability_options: capability_options_for(@attachment_recording))

      result = if attachment_params[:signed_blob_id].present?
                 RecordingStudioAttachable::Services::ReplaceAttachmentFile.call(
                   attachment_recording: @attachment_recording,
                   actor: current_attachable_actor,
                   signed_blob_id: attachment_params[:signed_blob_id],
                   name: attachment_params[:name],
                   description: attachment_params[:description]
                 )
               else
                 RecordingStudioAttachable::Services::ReviseAttachmentMetadata.call(
                   attachment_recording: @attachment_recording,
                   actor: current_attachable_actor,
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
      authorize_attachment_action!(:download, @attachment_recording.parent_recording || @attachment_recording,
                                   capability_options: capability_options_for(@attachment_recording))
      redirect_to main_app.rails_blob_path(@attachment_recording.recordable.file, disposition: :attachment)
    end

    private

    def attachment_params
      params.require(:attachment).permit(:name, :description, :signed_blob_id)
    end

    def capability_options_for(recording)
      owner_type = recording.recordable_type == RecordingStudioAttachable::Attachment.name ?
        recording.parent_recording&.recordable_type : recording.recordable_type
      RecordingStudio.capability_options(:attachable, for_type: owner_type) || {}
    end
  end
end
