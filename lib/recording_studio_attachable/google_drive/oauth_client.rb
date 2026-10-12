# frozen_string_literal: true

require "uri"

module RecordingStudioAttachable
  module GoogleDrive
    class OAuthClient
      class Error < RecordingStudioAttachable::Error; end

      AUTHORIZATION_ENDPOINT = "https://accounts.google.com/o/oauth2/v2/auth"
      TOKEN_ENDPOINT = "https://oauth2.googleapis.com/token"

      def initialize(configuration: RecordingStudioAttachable.configuration.google_drive)
        @configuration = configuration
      end

      def authorization_url(state:)
        ensure_configured!

        uri = URI(AUTHORIZATION_ENDPOINT)
        uri.query = URI.encode_www_form(
          access_type: configuration.access_type,
          client_id: configuration.client_id,
          include_granted_scopes: configuration.include_granted_scopes ? "true" : "false",
          prompt: configuration.prompt,
          redirect_uri: configuration.redirect_uri,
          response_type: "code",
          scope: Array(configuration.scopes).join(" "),
          state: state
        )
        uri.to_s
      end

      def exchange_code(code:)
        post_form(
          client_id: configuration.client_id,
          client_secret: configuration.client_secret,
          code: code,
          grant_type: "authorization_code",
          redirect_uri: configuration.redirect_uri
        )
      end

      def refresh_token(refresh_token:)
        post_form(
          client_id: configuration.client_id,
          client_secret: configuration.client_secret,
          grant_type: "refresh_token",
          refresh_token: refresh_token
        )
      end

      private

      attr_reader :configuration

      def ensure_configured!
        return if configuration.configured?

        raise RecordingStudioAttachable::DependencyUnavailableError,
              Copy.t(
                "google_drive.missing_credentials",
                default: "Google Drive addon is missing client credentials or redirect URI"
              )
      end

      def post_form(attributes)
        ensure_configured!
        response, body = Adapter::OauthHttp.post_form(TOKEN_ENDPOINT, attributes)
        raise Error, Adapter::OauthHttp.error_message(body, "Google Drive authentication failed") unless response.is_a?(Net::HTTPSuccess)

        Adapter::OauthHttp.normalize_tokens(body)
      end
    end
  end
end
