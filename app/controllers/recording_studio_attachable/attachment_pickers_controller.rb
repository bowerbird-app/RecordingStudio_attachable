# frozen_string_literal: true

module RecordingStudioAttachable
  class AttachmentPickersController < ApplicationController
    def index
      @recording = find_recording
      capability_options = capability_options_for(@recording)

      authorize_attachment_action!(:view, @recording, capability_options: capability_options)

      attachment_query = RecordingStudioAttachable::Queries::ForRecording.new(
        recording: @recording,
        scope: params[:scope],
        kind: :images,
        include_trashed: false,
        search: params[:q],
        page: params[:page],
        per_page: params[:per_page]
      )

      attachments = attachment_query.call

      render json: {
        attachments: attachments.map { |recording| attachment_json(recording) },
        pagination: {
          current_page: attachment_query.current_page,
          total_pages: attachment_query.total_pages,
          total_count: attachment_query.total_count,
          next_page: attachment_query.next_page?,
          previous_page: attachment_query.previous_page?
        }
      }
    end

    private

    def attachment_json(recording)
      attachment = recording.recordable
      blob_path = main_app.rails_blob_path(attachment.file, only_path: true)

      {
        id: recording.id,
        name: attachment.name,
        description: attachment.description,
        content_type: attachment.content_type,
        byte_size: attachment.byte_size,
        attachment_kind: attachment.attachment_kind,
        thumbnail_url: blob_path,
        insert_url: blob_path,
        alt: attachment.name,
        show_path: attachment_path(recording)
      }
    end
  end
end
