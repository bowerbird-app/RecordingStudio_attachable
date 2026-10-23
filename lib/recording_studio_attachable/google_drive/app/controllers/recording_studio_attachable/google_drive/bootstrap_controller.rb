# frozen_string_literal: true

module RecordingStudioAttachable
  module GoogleDrive
    class BootstrapController < ApplicationController
      def show
        authorize_google_drive_upload!
        ensure_google_drive_enabled!
        ensure_google_drive_picker_configured!

        render json: bootstrap_payload
      rescue RecordingStudioAttachable::DependencyUnavailableError => e
        render json: { error: e.message }, status: :unprocessable_content
      end

      private

      def bootstrap_payload
        payload = {
          provider_key: "google_drive",
          launcher: "google_drive",
          api_key: google_drive_configuration.api_key,
          app_id: google_drive_configuration.app_id,
          import_url: google_drive.recording_imports_path(@recording, format: :json, **attachment_redirect_params)
        }

        token, expires_at = Integration.picker_access(root: google_drive_root, actor: current_attachable_actor)
        payload[:access_token] = token
        payload[:expires_at] = expires_at.to_i if expires_at.respond_to?(:to_i) && expires_at.to_i.positive?
        payload
      rescue StandardError => e
        raise unless Integration.reconnect_required?(e)

        payload.merge(connect_url: google_drive_popup_connect_url)
      end
    end
  end
end
