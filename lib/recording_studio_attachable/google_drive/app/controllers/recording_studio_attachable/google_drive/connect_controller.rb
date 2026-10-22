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

        render_upload_provider_modal_event(
          type: "provider-auth-complete",
          provider_key: "google_drive",
          modal_id: current_upload_provider_modal_id,
          close_window: true
        )
      rescue RecordingStudioAttachable::DependencyUnavailableError => e
        dependency_unavailable_alert(e)
      end

      def destroy
        authorize_google_drive_upload!
        ensure_google_drive_enabled!
        disconnect_google_drive!

        redirect_to google_drive.recording_imports_path(@recording, upload_flow_params),
                    notice: Copy.legacy_t(
                      "google_drive.disconnected",
                      "google_drive.disconnected",
                      default: "Disconnected Google Drive."
                    )
      rescue RecordingStudioAttachable::DependencyUnavailableError => e
        dependency_unavailable_alert(e)
      end
    end
  end
end
