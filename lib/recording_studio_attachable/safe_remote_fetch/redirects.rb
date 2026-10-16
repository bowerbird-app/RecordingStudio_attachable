# frozen_string_literal: true

module RecordingStudioAttachable
  class SafeRemoteFetch
    module Redirects
      def follow_redirect(response, request)
        location = response["location"].to_s
        raise Error, "Remote download redirected without a location" if location.blank?

        perform(redirected_request(request, URI.join(request.uri.to_s, location), response.code))
      end

      def redirected_request(request, redirected, code)
        http_method, body = redirected_method_and_body(code, request.http_method, request.body)
        Transport::Request.new(
          uri: redirected,
          headers: headers_for_redirect(request.headers, from: request.uri, to: redirected),
          http_method: http_method,
          body: body,
          redirects_remaining: request.redirects_remaining - 1
        )
      end

      def redirected_method_and_body(code, http_method, body)
        status = code.to_s
        return ["GET", nil] if GET_ON_REDIRECT_CODES.include?(status)
        raise Error, "Remote download redirected a write request" if %w[307 308].include?(status) && http_method != "GET"

        [http_method, body]
      end

      def headers_for_redirect(headers, from:, to:)
        return headers.to_h.dup if from.host.to_s.casecmp(to.host.to_s).zero?

        {}
      end
    end
  end
end
