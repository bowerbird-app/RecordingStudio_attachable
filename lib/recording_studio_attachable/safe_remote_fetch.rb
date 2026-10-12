# frozen_string_literal: true

require "ipaddr"
require "net/http"
require "resolv"
require "tempfile"
require "uri"

module RecordingStudioAttachable
  # rubocop:disable Metrics/ClassLength, Metrics/MethodLength, Metrics/AbcSize, Metrics/ParameterLists
  class SafeRemoteFetch
    class Error < RecordingStudioAttachable::Error; end

    MAX_REDIRECTS = 5
    OPEN_TIMEOUT = 10
    READ_TIMEOUT = 30
    SSL_TIMEOUT = 10
    WRITE_TIMEOUT = 30
    DEADLINE_SECONDS = 60
    GET_ON_REDIRECT_CODES = %w[301 302 303].freeze
    PRIVATE_NETWORKS = [
      IPAddr.new("0.0.0.0/8"),
      IPAddr.new("10.0.0.0/8"),
      IPAddr.new("100.64.0.0/10"),
      IPAddr.new("127.0.0.0/8"),
      IPAddr.new("169.254.0.0/16"),
      IPAddr.new("172.16.0.0/12"),
      IPAddr.new("192.168.0.0/16"),
      IPAddr.new("198.18.0.0/15"),
      IPAddr.new("224.0.0.0/4"),
      IPAddr.new("::/128"),
      IPAddr.new("::1/128"),
      IPAddr.new("64:ff9b::/96"),
      IPAddr.new("fc00::/7"),
      IPAddr.new("fe80::/10"),
      IPAddr.new("::ffff:0.0.0.0/104"),
      IPAddr.new("::ffff:10.0.0.0/104"),
      IPAddr.new("::ffff:100.64.0.0/106"),
      IPAddr.new("::ffff:127.0.0.0/104"),
      IPAddr.new("::ffff:169.254.0.0/112"),
      IPAddr.new("::ffff:172.16.0.0/108"),
      IPAddr.new("::ffff:192.168.0.0/112"),
      IPAddr.new("::ffff:198.18.0.0/111"),
      IPAddr.new("::ffff:224.0.0.0/100")
    ].freeze
    BLOCKED_HOSTS = %w[localhost metadata.google.internal].freeze

    Result = Struct.new(:io, :content_type, :byte_size, keyword_init: true)

    def self.tls_start_options(ipaddr: nil, remaining: nil)
      timeout_budget = remaining || DEADLINE_SECONDS
      {
        use_ssl: true,
        open_timeout: [OPEN_TIMEOUT, timeout_budget].min,
        read_timeout: [READ_TIMEOUT, timeout_budget].min,
        ssl_timeout: [SSL_TIMEOUT, timeout_budget].min,
        write_timeout: [WRITE_TIMEOUT, timeout_budget].min,
        ipaddr: ipaddr
      }.compact
    end

    def self.close_io(io)
      return if io.nil?

      io.respond_to?(:close!) ? io.close! : io.close
    rescue IOError
      nil
    end

    def self.call(remote_file, max_bytes:)
      new(remote_file: remote_file, max_bytes: max_bytes).call
    end

    def initialize(remote_file:, max_bytes:)
      @remote_file = remote_file
      @max_bytes = max_bytes.to_i
    end

    def call
      raise Error, "Maximum download size must be positive" unless max_bytes.positive?
      raise Error, "Remote file exceeds maximum file size" if remote_file.byte_size && remote_file.byte_size > max_bytes

      @deadline_at = monotonic_now + DEADLINE_SECONDS
      perform_request(
        uri: remote_file.uri,
        headers: remote_file.headers,
        method: remote_file.http_method,
        body: remote_file.body,
        redirects_remaining: MAX_REDIRECTS
      )
    end

    private

    attr_reader :remote_file, :max_bytes, :deadline_at

    def perform_request(uri:, headers:, method:, body:, redirects_remaining:)
      raise Error, "Remote download redirected too many times" if redirects_remaining.negative?

      validate_uri!(uri)
      ipaddr = resolved_public_ip(uri.host)
      request = build_request(uri, headers, method: method, body: body)

      start_options = self.class.tls_start_options(ipaddr: ipaddr, remaining: remaining_seconds)
      Net::HTTP.start(uri.host, uri.port, **start_options) do |http|
        return dispatch_request(
          http,
          request,
          uri: uri,
          headers: headers,
          method: method,
          body: body,
          redirects_remaining: redirects_remaining
        )
      end
    end

    def dispatch_request(http, request, uri:, headers:, method:, body:, redirects_remaining:)
      handled = false
      result = nil
      returned = http.request(request) do |http_response|
        handled = true
        result = handle_response(
          http_response,
          uri: uri,
          headers: headers,
          method: method,
          body: body,
          redirects_remaining: redirects_remaining
        )
      end

      return result if handled

      handle_response(
        returned,
        uri: uri,
        headers: headers,
        method: method,
        body: body,
        redirects_remaining: redirects_remaining
      )
    end

    def handle_response(response, uri:, headers:, method:, body:, redirects_remaining:)
      if response.is_a?(Net::HTTPRedirection)
        return follow_redirect(
          response,
          uri: uri,
          headers: headers,
          method: method,
          body: body,
          redirects_remaining: redirects_remaining
        )
      end

      raise Error, "Remote download failed (HTTP #{response.code})" unless response.is_a?(Net::HTTPSuccess)

      validate_content_length!(response)
      io = stream_body(response)
      Result.new(
        io: io,
        content_type: normalized_content_type(response["content-type"]) || remote_file.content_type,
        byte_size: io.size
      )
    end

    def normalized_content_type(value)
      value.to_s.split(";").first.presence
    end

    def follow_redirect(response, uri:, headers:, method:, body:, redirects_remaining:)
      location = response["location"].to_s
      raise Error, "Remote download redirected without a location" if location.blank?

      redirected_uri = URI.join(uri.to_s, location)
      next_method, next_body = redirected_method_and_body(response.code, method, body)

      perform_request(
        uri: redirected_uri,
        headers: headers_for_redirect(headers, from: uri, to: redirected_uri),
        method: next_method,
        body: next_body,
        redirects_remaining: redirects_remaining - 1
      )
    end

    def redirected_method_and_body(code, method, body)
      status = code.to_s
      return ["GET", nil] if GET_ON_REDIRECT_CODES.include?(status)
      raise Error, "Remote download redirected a write request" if %w[307 308].include?(status) && method != "GET"

      [method, body]
    end

    def headers_for_redirect(headers, from:, to:)
      next_headers = headers.to_h.dup
      return next_headers if from.host.to_s.downcase == to.host.to_s.downcase

      next_headers.reject { |key, _value| key.to_s.casecmp("Authorization").zero? }
    end

    def build_request(uri, headers, method:, body:)
      request = case method
                when "POST"
                  Net::HTTP::Post.new(uri)
                when "PUT"
                  Net::HTTP::Put.new(uri)
                else
                  Net::HTTP::Get.new(uri)
                end
      headers.each { |key, value| request[key] = value }
      request.body = body if body && request.request_body_permitted?
      request
    end

    def validate_uri!(uri)
      raise Error, "Remote download must use HTTPS" unless uri.is_a?(URI::HTTPS)
      raise Error, "Remote download host is missing" if uri.host.blank?
      raise Error, "Remote download must use port 443" unless uri.port.nil? || uri.port == 443
      raise Error, "Remote download host is not allowed" unless host_allowed?(uri.host)
      raise Error, "Remote download host is not allowed" if blocked_host?(uri.host)
    end

    def host_allowed?(host)
      normalized = host.to_s.downcase
      remote_file.allowed_hosts.any? do |pattern|
        allowed = pattern.to_s.downcase
        if allowed.start_with?("*.")
          suffix = allowed.delete_prefix("*.")
          normalized == suffix || normalized.end_with?(".#{suffix}")
        else
          normalized == allowed
        end
      end
    end

    def blocked_host?(host)
      BLOCKED_HOSTS.include?(host.to_s.downcase)
    end

    def resolved_public_ip(host)
      addresses = addresses_for(host)
      raise Error, "Remote download host could not be resolved" if addresses.empty?
      raise Error, "Remote download host resolves to a private address" if addresses.any? { |address| private_ip?(address) }

      addresses.first
    end

    def addresses_for(host)
      Resolv.getaddresses(host.to_s)
    rescue Resolv::ResolvError, SocketError
      raise Error, "Remote download host could not be resolved"
    end

    def private_ip?(address)
      ip = IPAddr.new(address)
      PRIVATE_NETWORKS.any? { |network| network.include?(ip) }
    rescue IPAddr::InvalidAddressError
      true
    end

    def validate_content_length!(response)
      content_length = response["content-length"].presence&.to_i
      return if content_length.blank?

      raise Error, "Remote file exceeds maximum file size" if content_length > max_bytes
    end

    def stream_body(response)
      tempfile = Tempfile.new(["recording-studio-attachable-fetch", File.extname(remote_file.filename.to_s)])
      tempfile.binmode
      written = 0

      each_body_chunk(response) do |chunk|
        enforce_deadline!
        written += chunk.bytesize
        raise Error, "Remote file exceeds maximum file size" if written > max_bytes

        tempfile.write(chunk)
      end

      tempfile.flush
      tempfile.rewind
      tempfile
    rescue StandardError
      tempfile&.close!
      raise
    end

    def each_body_chunk(response)
      raise Error, "Remote download body could not be streamed" unless response.respond_to?(:read_body)

      response.read_body do |chunk|
        yield chunk.to_s
      end
    end

    def remaining_seconds
      remaining = deadline_at - monotonic_now
      raise Error, "Remote download timed out" if remaining <= 0

      remaining
    end

    def enforce_deadline!
      remaining_seconds
    end

    def monotonic_now
      Process.clock_gettime(Process::CLOCK_MONOTONIC)
    end
  end
  # rubocop:enable Metrics/ClassLength, Metrics/MethodLength, Metrics/AbcSize, Metrics/ParameterLists
end
