# frozen_string_literal: true

module RecordingStudioAttachable
  module GoogleDrive
    class ConnectController < ApplicationController
      def show
        authorize_google_drive_upload!
        ensure_google_drive_enabled!

        @oauth_connect_path = google_drive_oauth_connect_path
        @oauth_return_to = google_drive_connect_return_path(popup: params[:popup].to_s == "1")
        @auto_submit = params[:popup].to_s == "1"
        @reconnect = google_drive_reconnect?
        render :show
      rescue RecordingStudioAttachable::DependencyUnavailableError => e
        dependency_unavailable_alert(e)
      end

      def complete
        authorize_google_drive_upload!
        ensure_google_drive_enabled!
        render_connect_complete
      rescue RecordingStudioAttachable::DependencyUnavailableError => e
        dependency_unavailable_alert(e)
      end

      def destroy
        authorize_google_drive_upload!
        ensure_google_drive_enabled!
        redirect_after_disconnect(disconnect_google_drive)
      rescue RecordingStudioAttachable::DependencyUnavailableError => e
        dependency_unavailable_alert(e)
      end

      private

      def render_connect_complete
        render_upload_provider_modal_event(
          type: "provider-auth-complete",
          provider_key: "google_drive",
          modal_id: current_upload_provider_modal_id,
          reload_url: google_drive_connect_reload_url,
          close_window: true
        )
      end

      def redirect_after_disconnect(oauth_disconnect_path)
        if oauth_disconnect_path.present?
          redirect_to oauth_disconnect_path, status: :temporary_redirect
        else
          redirect_to google_drive.recording_imports_path(@recording, upload_flow_params),
                      alert: Copy.t(
                        "google_drive.disconnect_failed",
                        default: "Google Drive isn't connected."
                      )
        end
      end
    end
  end
end
