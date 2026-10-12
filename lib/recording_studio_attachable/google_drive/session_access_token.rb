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

      def default_configuration
        RecordingStudioAttachable.configuration.google_drive
      end

      def build_oauth_client
        RecordingStudioAttachable::GoogleDrive::OAuthClient.new(configuration: configuration)
      end
    end
  end
end
