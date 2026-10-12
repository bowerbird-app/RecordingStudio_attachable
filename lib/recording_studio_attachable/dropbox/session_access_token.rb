# frozen_string_literal: true

module RecordingStudioAttachable
  module Dropbox
    class SessionAccessToken < RecordingStudioAttachable::SessionAccessToken
      private

      def session_key
        "recording_studio_attachable_dropbox"
      end

      def provider_name
        "Dropbox"
      end

      def default_configuration
        RecordingStudioAttachable.configuration.dropbox
      end

      def build_oauth_client
        RecordingStudioAttachable::Dropbox::OAuthClient.new(configuration: configuration)
      end
    end
  end
end
