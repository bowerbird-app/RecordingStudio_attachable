# frozen_string_literal: true

require "net/http"
require_relative "redirects"

module RecordingStudioAttachable
  class SafeRemoteFetch
    class Transport
      include Redirects

      Request = Struct.new(:uri, :headers, :http_method, :body, :redirects_remaining, keyword_init: true)

      def initialize(remote_file:, size_limit:, host_guard:)
        @remote_file = remote_file
        @size_limit = size_limit
        @host_guard = host_guard
        @deadline = Deadline.new(DEADLINE_SECONDS)
      end

      def call
        perform(initial_request)
      end

      private

      attr_reader :remote_file, :size_limit, :host_guard, :deadline

      def initial_request
        Request.new(
          uri: remote_file.uri,
          headers: remote_file.headers,
          http_method: remote_file.http_method,
          body: remote_file.body,
          redirects_remaining: MAX_REDIRECTS
        )
      end

      def perform(request)
        raise Error, "Remote download redirected too many times" if request.redirects_remaining.negative?

        host_guard.validate!(request.uri)
        http_request = build_request(request)
        start_http(request, http_request)
      end

      def start_http(request, http_request)
        ipaddr = host_guard.public_ip(request.uri.host)
        options = SafeRemoteFetch.tls_start_options(ipaddr: ipaddr, remaining: deadline.remaining)
        Net::HTTP.start(request.uri.host, request.uri.port, **options) do |http|
          return dispatch(http, http_request, request)
        end
      end

      def dispatch(http, http_request, request)
        handled = false
        result = nil
        returned = http.request(http_request) do |http_response|
          handled = true
          result = handle_response(http_response, request)
        end

        handled ? result : handle_response(returned, request)
      end

      def handle_response(response, request)
        return follow_redirect(response, request) if response.is_a?(Net::HTTPRedirection)

        success_result(response)
      end

      def success_result(response)
        raise Error, "Remote download failed (HTTP #{response.code})" unless response.is_a?(Net::HTTPSuccess)

        write_success(response)
      end

      def write_success(response)
        size_limit.check!(response["content-length"].presence&.to_i)
        io = body_writer.write(response)
        Result.new(io: io, content_type: content_type_for(response), byte_size: io.size)
      end

      def body_writer
        BodyWriter.new(filename: remote_file.filename, size_limit: size_limit, deadline: deadline)
      end

      def content_type_for(response)
        response["content-type"].to_s.split(";").first.presence || remote_file.content_type
      end

      def build_request(request)
        http_request = http_class_for(request.http_method).new(request.uri)
        request.headers.each { |key, value| http_request[key] = value }
        http_request.body = request.body if request.body && http_request.request_body_permitted?
        http_request
      end

      def http_class_for(http_method)
        case http_method
        when "POST" then Net::HTTP::Post
        when "PUT" then Net::HTTP::Put
        else Net::HTTP::Get
        end
      end
    end
  end
end
