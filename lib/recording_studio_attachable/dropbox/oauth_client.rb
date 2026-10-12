# frozen_string_literal: true

require "base64"
require "digest"
require "securerandom"
require "uri"

module RecordingStudioAttachable
  module Dropbox
    class OAuthClient
      include RecordingStudioAttachable::Adapter::OauthClient

      class Error < RecordingStudioAttachable::Error; end

      AUTHORIZATION_ENDPOINT = "https://www.dropbox.com/oauth2/authorize"
      TOKEN_ENDPOINT = "https://api.dropboxapi.com/oauth2/token"

      def self.generate_code_verifier
        SecureRandom.urlsafe_base64(32).delete("=")
      end

      def self.code_challenge(code_verifier)
        Base64.urlsafe_encode64(Digest::SHA256.digest(code_verifier), padding: false)
      end

      def initialize(configuration: RecordingStudioAttachable.configuration.dropbox)
        @configuration = configuration
      end

      def authorization_url(state:, code_challenge:)
        ensure_configured!

        uri = URI(AUTHORIZATION_ENDPOINT)
        uri.query = URI.encode_www_form(authorization_params(state:, code_challenge:))
        uri.to_s
      end

      def exchange_code(code:, code_verifier:)
        post_form(
          client_id: configuration.client_id,
          client_secret: configuration.client_secret,
          code: code,
          code_verifier: code_verifier,
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

      def authorization_params(state:, code_challenge:)
        pkce_params(code_challenge).merge(client_params(state))
      end

      def pkce_params(code_challenge)
        { code_challenge: code_challenge, code_challenge_method: "S256", token_access_type: "offline" }
      end

      def client_params(state)
        {
          client_id: configuration.client_id,
          redirect_uri: configuration.redirect_uri,
          response_type: "code",
          scope: Array(configuration.scopes).join(" "),
          state: state
        }
      end

      def missing_credentials_message
        "Dropbox addon is missing client credentials or redirect URI"
      end

      def authentication_failed_message
        "Dropbox authentication failed"
      end
    end
  end
end
