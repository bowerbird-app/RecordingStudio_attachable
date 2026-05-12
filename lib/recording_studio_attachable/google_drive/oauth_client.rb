# frozen_string_literal: true

require "json"
require "net/http"
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
              "Google Drive addon is missing client credentials or redirect URI"
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
        raise Error, response_error_message(body, "Google Drive authentication failed") unless response.is_a?(Net::HTTPSuccess)

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
