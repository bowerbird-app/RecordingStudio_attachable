# frozen_string_literal: true

module RecordingStudioAttachable
  module GoogleDrive
    class SessionAccessToken < RecordingStudioAttachable::SessionAccessToken
      private

      def session_key
        "recording_studio_attachable_google_drive"
      end

      def provider_name
        "Google Drive"
      end

      def connect_message
        Copy.t("google_drive.connect_before_import", default: "Connect Google Drive before importing files")
      end

      def reconnect_message
        Copy.t("google_drive.reconnect_to_continue", default: "Reconnect Google Drive to continue")
      end

      def default_configuration
        RecordingStudioAttachable.configuration.google_drive
      end

      def build_oauth_client
        RecordingStudioAttachable::GoogleDrive::OAuthClient.new(configuration: configuration)
      end
    end
  end
end
