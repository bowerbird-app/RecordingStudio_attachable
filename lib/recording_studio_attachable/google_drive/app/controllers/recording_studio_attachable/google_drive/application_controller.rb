# frozen_string_literal: true

module RecordingStudioAttachable
  module GoogleDrive
    class ApplicationController < RecordingStudioAttachable::ApplicationController
      helper_method :google_drive_connected?, :google_drive_reconnect?

      private

      def google_drive_configuration
        RecordingStudioAttachable.configuration.google_drive
      end

      def ensure_google_drive_enabled!
        unless google_drive_configuration.enabled? && Integration.gem_loaded?
          raise RecordingStudioAttachable::DependencyUnavailableError,
                Copy.t("google_drive.not_enabled", default: "Google Drive isn't available right now")
        end
      end

      def ensure_google_drive_picker_configured!
        return if google_drive_configuration.picker_configured?

        raise RecordingStudioAttachable::DependencyUnavailableError,
              Copy.t(
                "google_drive.picker_requires_config",
                default: "Google Drive picker needs an API key and app id"
              )
      end

      def authorize_google_drive_upload!
        @recording = find_recording
        authorize_attachment_action!(:upload, @recording, capability_options: capability_options_for(@recording))
      end

      def google_drive_root
        recording = @recording || find_recording
        return recording unless recording.respond_to?(:root_recording)

        recording.root_recording || recording
      end

      def google_drive_client
        Integration.client(root: google_drive_root, actor: current_attachable_actor)
      end

      def google_drive_connection
        Integration.connection(root: google_drive_root, actor: current_attachable_actor)
      end

      def google_drive_live_connection
        Integration.live_connection(root: google_drive_root, actor: current_attachable_actor)
      end

      def google_drive_connected?
        google_drive_connection.present?
      end

      def google_drive_reconnect?
        live = google_drive_live_connection
        live.present? && live.respond_to?(:needs_reconnect?) && live.needs_reconnect?
      end

      def google_drive_oauth
        return unless Integration.oauth_loaded? && main_app.respond_to?(:recording_studio_oauth)

        main_app.recording_studio_oauth
      end

      def google_drive_oauth_connect_path
        google_drive_oauth&.outbound_connect_path(provider: Integration.provider_key)
      end

      def google_drive_popup_connect_url
        recording_connect_path(
          @recording,
          popup: 1,
          provider_key: "google_drive",
          **attachment_redirect_params
        )
      end

      def google_drive_connect_return_path(popup:)
        if popup
          google_drive.recording_connected_path(@recording, **upload_flow_params.merge(popup: 1))
        else
          google_drive.recording_imports_path(@recording, **upload_flow_params)
        end
      end

      def disconnect_google_drive!
        connection = google_drive_live_connection
        return if connection.nil? || !defined?(::RecordingStudioOauth::Services::DisconnectOutboundConnection)

        ::RecordingStudioOauth::Services::DisconnectOutboundConnection.call(
          connection: connection,
          actor: current_attachable_actor
        )
      end

      def dependency_unavailable_alert(error)
        redirect_to recording_studio_attachable.recording_attachment_upload_path(
          @recording || find_recording,
          attachment_redirect_params
        ), alert: error.message
      end
    end
  end
end
