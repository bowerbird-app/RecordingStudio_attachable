# frozen_string_literal: true

module RecordingStudioAttachable
  module GoogleDrive
    class BootstrapController < ApplicationController
      def show
        authorize_google_drive_upload!
        ensure_google_drive_enabled!
        ensure_google_drive_picker_configured!

        render json: bootstrap_payload
      rescue RecordingStudioAttachable::DependencyUnavailableError, RecordingStudioAttachable::Error => e
        render json: { error: e.message }, status: :unprocessable_entity
      end

      private

      def bootstrap_payload
        payload = {
          provider_key: "google_drive",
          launcher: "google_drive",
          client_id: google_drive_configuration.client_id,
          api_key: google_drive_configuration.api_key,
          app_id: google_drive_configuration.app_id,
          scopes: Array(google_drive_configuration.scopes),
          import_url: google_drive.recording_imports_path(@recording, format: :json, **attachment_redirect_params)
        }

        payload[:access_token] = current_google_drive_access_token
        payload
      rescue RecordingStudioAttachable::Error
        payload.merge(
          auth_url: oauth_client.authorization_url(
            state: store_google_drive_state!(recording_id: @recording.id, popup: true, provider_key: "google_drive",
                                             redirect_params: attachment_redirect_params)
          )
        )
      end
    end
  end
end
