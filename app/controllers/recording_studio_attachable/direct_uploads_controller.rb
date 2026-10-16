# frozen_string_literal: true

module RecordingStudioAttachable
  class DirectUploadsController < ApplicationController
    include ActiveStorage::SetCurrent

    def create
      recording = find_recording
      authorize_attachment_action!(:upload, recording)
      blob = DirectUpload.prepare!(recording: recording, actor: current_attachable_actor, **upload_attributes)
      render json: DirectUpload.browser_json(blob)
    rescue ArgumentError, RecordingStudioAttachable::Error => e
      render json: { error: e.message }, status: :unprocessable_content
    rescue StandardError => e
      raise unless plan_limit?(e)

      render json: { error: e.message }, status: :unprocessable_content
    end

    private

    def upload_attributes
      permitted = params.expect(blob: %i[filename byte_size checksum content_type])
      {
        filename: permitted[:filename],
        byte_size: permitted[:byte_size],
        checksum: permitted[:checksum],
        content_type: permitted[:content_type]
      }
    end

    def plan_limit?(error)
      defined?(::RecordingStudioStripe::PlanLimitReached) && error.is_a?(::RecordingStudioStripe::PlanLimitReached)
    end
  end
end
