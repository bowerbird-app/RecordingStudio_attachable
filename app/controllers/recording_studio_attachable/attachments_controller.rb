# frozen_string_literal: true

module RecordingStudioAttachable
  class AttachmentsController < ApplicationController
    include AttachmentFileButtonResponses

    def show
      @attachment_recording = find_attachment_recording
      authorize_attachment_owner_action!(:view, @attachment_recording)

      @attachment = @attachment_recording.recordable
      @replace_allowed_content_types = configured_attachable_option(@attachment_recording, :allowed_content_types)
      @replace_max_file_size = configured_attachable_option(@attachment_recording, :max_file_size)
      @image_processing_enabled = configured_attachable_option(@attachment_recording, :image_processing_enabled)
      @image_processing_max_width = configured_attachable_option(@attachment_recording, :image_processing_max_width)
      @image_processing_max_height = configured_attachable_option(@attachment_recording, :image_processing_max_height)
      @image_processing_quality = configured_attachable_option(@attachment_recording, :image_processing_quality)
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

      redirect_params = attachment_navigation_params
      file_replacement = attachment_params[:signed_blob_id].present?
      parent_return_to = AttachmentFileButton.return_to_from(redirect_params)

      if result.success?
        redirect_to success_path_for(result.value, file_replacement, parent_return_to, redirect_params),
                    status: :see_other,
                    notice: success_notice_for(file_replacement, parent_return_to)
      else
        redirect_to failure_path_for(@attachment_recording, file_replacement, parent_return_to, redirect_params),
                    status: :see_other,
                    alert: result.error
      end
    end

    def download
      @attachment_recording = find_attachment_recording
      authorize_attachment_owner_action!(:download, @attachment_recording)

      send_attachment_data(@attachment_recording, disposition: :attachment)
    end

    def file
      @attachment_recording = find_attachment_recording
      authorize_attachment_owner_action!(:view, @attachment_recording)

      send_attachment_data(@attachment_recording, disposition: :inline)
    end

    def preview
      @attachment_recording = find_attachment_recording
      authorize_attachment_owner_action!(:view, @attachment_recording)

      preview_target = @attachment_recording.recordable.preview_target_named(params[:variant_name])
      raise ActiveRecord::RecordNotFound if preview_target.blank?

      send_preview_data(@attachment_recording.recordable, preview_target)
    end

    private

    def attachment_params
      params.expect(attachment: %i[name description signed_blob_id])
    end

    def send_attachment_data(attachment_recording, disposition:)
      attachment = attachment_recording.recordable
      send_data \
        attachment.file.download,
        filename: attachment.original_filename,
        type: attachment.content_type,
        disposition: disposition
    end

    def send_preview_data(attachment, preview_target)
      data = if attachment.file.variable?
               preview_target.processed.download
             else
               attachment.file.download
             end

      send_data data, filename: attachment.original_filename, type: attachment.content_type, disposition: :inline
    end
  end
end
