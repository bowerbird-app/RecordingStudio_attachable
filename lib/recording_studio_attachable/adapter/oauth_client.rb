# frozen_string_literal: true

module RecordingStudioAttachable
  module Adapter
    module OauthClient
      def ensure_configured!
        return if configuration.configured?

        raise RecordingStudioAttachable::DependencyUnavailableError, missing_credentials_message
      end

      def post_form(attributes)
        ensure_configured!
        response, body = OauthHttp.post_form(self.class::TOKEN_ENDPOINT, attributes)
        raise self.class::Error, OauthHttp.error_message(body, authentication_failed_message) unless response.is_a?(Net::HTTPSuccess)

        OauthHttp.normalize_tokens(body)
      end
    end
  end
end
