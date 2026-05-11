# frozen_string_literal: true

module RecordingStudioAttachable
  module GoogleDrive
    class SessionAccessToken
      def self.fetch(session:, configuration: RecordingStudioAttachable.configuration.google_drive, oauth_client: nil)
        new(session:, configuration: configuration, oauth_client: oauth_client).fetch
      end

      def initialize(session:, configuration: RecordingStudioAttachable.configuration.google_drive, oauth_client: nil)
        @session = session
        @configuration = configuration
        @oauth_client = oauth_client
      end

      def fetch
        access_token = current_access_token
        return access_token unless refresh_needed?

        refresh_token = current_refresh_token
        refreshed_access_token(refresh_token)
      end

      private

      attr_reader :session, :configuration

      def current_access_token
        tokens["access_token"].presence || raise(RecordingStudioAttachable::Error, "Connect Google Drive before importing files")
      end

      def current_refresh_token
        tokens["refresh_token"].presence || raise(RecordingStudioAttachable::Error, "Reconnect Google Drive to continue")
      end

      def refreshed_access_token(refresh_token)
        refreshed = oauth_client.refresh_token(refresh_token: refresh_token)
        merged = merged_tokens(refreshed)
        storage["tokens"] = merged
        merged.fetch("access_token")
      end

      def merged_tokens(refreshed)
        tokens.merge(refreshed.slice("access_token", "refresh_token", "expires_at"))
      end

      def storage
        session["recording_studio_attachable_google_drive"] ||= {}
      end

      def tokens
        storage.fetch("tokens", {})
      end

      def refresh_needed?
        expires_at = tokens["expires_at"].to_i
        expires_at.positive? && expires_at <= Time.current.to_i + 30
      end

      def oauth_client
        @oauth_client ||= RecordingStudioAttachable::GoogleDrive::OAuthClient.new(configuration: configuration)
      end
    end
  end
end
