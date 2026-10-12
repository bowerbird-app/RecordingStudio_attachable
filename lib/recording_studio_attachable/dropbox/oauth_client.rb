# frozen_string_literal: true

require "base64"
require "digest"
require "json"
require "net/http"
require "securerandom"
require "uri"

module RecordingStudioAttachable
  module Dropbox
    class OAuthClient
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
        uri.query = URI.encode_www_form(
          client_id: configuration.client_id,
          code_challenge: code_challenge,
          code_challenge_method: "S256",
          redirect_uri: configuration.redirect_uri,
          response_type: "code",
          scope: Array(configuration.scopes).join(" "),
          state: state,
          token_access_type: "offline"
        )
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

      def ensure_configured!
        return if configuration.configured?

        raise RecordingStudioAttachable::DependencyUnavailableError,
              "Dropbox addon is missing client credentials or redirect URI"
      end

      def post_form(attributes)
        ensure_configured!

        uri = URI(TOKEN_ENDPOINT)
        request = Net::HTTP::Post.new(uri)
        request.set_form_data(attributes)

        response = Net::HTTP.start(uri.host, uri.port, use_ssl: true) do |http|
          http.request(request)
        end

        body = parse_json(response.body)
        raise Error, response_error_message(body, "Dropbox authentication failed") unless response.is_a?(Net::HTTPSuccess)

        normalize_token_response(body)
      end

      def normalize_token_response(body)
        expires_in = body["expires_in"].to_i
        return body unless expires_in.positive?

        body.merge("expires_at" => Time.current.to_i + expires_in)
      end

      def parse_json(body)
        JSON.parse(body.to_s)
      rescue JSON::ParserError
        {}
      end

      def response_error_message(body, default_message)
        body["error_description"].presence || body["error"].presence || default_message
      end
    end
  end
end
