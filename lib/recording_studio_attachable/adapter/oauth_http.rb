# frozen_string_literal: true

require "net/http"
require "uri"

module RecordingStudioAttachable
  module Adapter
    module OauthHttp
      module_function

      def post_form(endpoint, attributes)
        uri = URI(endpoint)
        request = Net::HTTP::Post.new(uri)
        request.set_form_data(attributes)
        response = start_request(uri, request)
        [response, RecordingStudioAttachable::JsonBody.parse(response.body)]
      end

      def start_request(uri, request)
        Net::HTTP.start(uri.host, uri.port, **RecordingStudioAttachable::SafeRemoteFetch.tls_start_options) do |http|
          http.request(request)
        end
      end

      def normalize_tokens(body)
        expires_in = body["expires_in"].to_i
        return body unless expires_in.positive?

        body.merge("expires_at" => Time.current.to_i + expires_in)
      end

      def error_message(body, default_message)
        body["error_description"].presence || body["error"].presence || default_message
      end
    end
  end
end
