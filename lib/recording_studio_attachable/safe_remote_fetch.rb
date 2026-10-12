# frozen_string_literal: true

require "ipaddr"
require "net/http"
require "resolv"
require "tempfile"
require "uri"

module RecordingStudioAttachable
  # rubocop:disable Metrics/ClassLength, Metrics/MethodLength, Metrics/AbcSize, Metrics/CyclomaticComplexity
  class SafeRemoteFetch
    class Error < RecordingStudioAttachable::Error; end

    MAX_REDIRECTS = 5
    OPEN_TIMEOUT = 10
    READ_TIMEOUT = 30
    PRIVATE_NETWORKS = [
      IPAddr.new("0.0.0.0/8"),
      IPAddr.new("10.0.0.0/8"),
      IPAddr.new("127.0.0.0/8"),
      IPAddr.new("169.254.0.0/16"),
      IPAddr.new("172.16.0.0/12"),
      IPAddr.new("192.168.0.0/16"),
      IPAddr.new("::1/128"),
      IPAddr.new("fc00::/7"),
      IPAddr.new("fe80::/10"),
      IPAddr.new("::ffff:127.0.0.0/104"),
      IPAddr.new("::ffff:10.0.0.0/104"),
      IPAddr.new("::ffff:169.254.0.0/112"),
      IPAddr.new("::ffff:172.16.0.0/108"),
      IPAddr.new("::ffff:192.168.0.0/112")
    ].freeze
    BLOCKED_HOSTS = %w[localhost metadata.google.internal].freeze

    Result = Struct.new(:io, :content_type, :byte_size, keyword_init: true)

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

      perform_request(
        uri: remote_file.uri,
        headers: remote_file.headers,
        redirects_remaining: MAX_REDIRECTS
      )
    end

    private

    attr_reader :remote_file, :max_bytes

    def perform_request(uri:, headers:, redirects_remaining:)
      raise Error, "Remote download redirected too many times" if redirects_remaining.negative?

      validate_uri!(uri)

      request = build_request(uri, headers)

      Net::HTTP.start(uri.host, uri.port, use_ssl: true) do |http|
        apply_timeouts!(http)
        return dispatch_request(http, request, uri: uri, headers: headers, redirects_remaining: redirects_remaining)
      end
    end

    def apply_timeouts!(http)
      http.open_timeout = OPEN_TIMEOUT if http.respond_to?(:open_timeout=)
      http.read_timeout = READ_TIMEOUT if http.respond_to?(:read_timeout=)
    end

    def dispatch_request(http, request, uri:, headers:, redirects_remaining:)
      handled = false
      result = nil
      returned = http.request(request) do |http_response|
        handled = true
        result = handle_response(http_response, uri: uri, headers: headers, redirects_remaining: redirects_remaining)
      end

      handled ? result : handle_response(returned, uri: uri, headers: headers, redirects_remaining: redirects_remaining)
    end

    def handle_response(response, uri:, headers:, redirects_remaining:)
      if response.is_a?(Net::HTTPRedirection)
        return follow_redirect(response, uri: uri, headers: headers, redirects_remaining: redirects_remaining)
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

    def follow_redirect(response, uri:, headers:, redirects_remaining:)
      location = response["location"].to_s
      raise Error, "Remote download redirected without a location" if location.blank?

      redirected_uri = URI.join(uri.to_s, location)
      next_headers = headers.dup
      next_headers.delete("Authorization") if redirected_uri.host.to_s.downcase != uri.host.to_s.downcase

      perform_request(uri: redirected_uri, headers: next_headers, redirects_remaining: redirects_remaining - 1)
    end

    def build_request(uri, headers)
      request = case remote_file.http_method
                when "POST"
                  Net::HTTP::Post.new(uri)
                when "PUT"
                  Net::HTTP::Put.new(uri)
                else
                  Net::HTTP::Get.new(uri)
                end
      headers.each { |key, value| request[key] = value }
      request.body = remote_file.body if remote_file.body && request.request_body_permitted?
      request
    end

    def validate_uri!(uri)
      raise Error, "Remote download must use HTTPS" unless uri.is_a?(URI::HTTPS)
      raise Error, "Remote download host is missing" if uri.host.blank?
      raise Error, "Remote download must use port 443" unless uri.port.nil? || uri.port == 443
      raise Error, "Remote download host is not allowed" unless host_allowed?(uri.host)
      raise Error, "Remote download host is not allowed" if blocked_host?(uri.host)
      raise Error, "Remote download host resolves to a private address" if private_address?(uri.host)
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

    def private_address?(host)
      addresses_for(host).any? { |address| private_ip?(address) }
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
      if response.respond_to?(:read_body)
        streamed = false
        response.read_body do |chunk|
          streamed = true
          yield chunk.to_s
        end
        return if streamed
      end

      yield response.body.to_s
    end
  end
  # rubocop:enable Metrics/ClassLength, Metrics/MethodLength, Metrics/AbcSize, Metrics/CyclomaticComplexity
end
