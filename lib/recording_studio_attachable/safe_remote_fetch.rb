# frozen_string_literal: true

require "net/http"
require "uri"
require_relative "safe_remote_fetch/host_guard"
require_relative "safe_remote_fetch/size_limit"
require_relative "safe_remote_fetch/deadline"
require_relative "safe_remote_fetch/body_writer"
require_relative "safe_remote_fetch/transport"

module RecordingStudioAttachable
  class SafeRemoteFetch
    class Error < RecordingStudioAttachable::Error; end

    MAX_REDIRECTS = 5
    OPEN_TIMEOUT = 10
    READ_TIMEOUT = 30
    SSL_TIMEOUT = 10
    WRITE_TIMEOUT = 30
    DEADLINE_SECONDS = 60
    GET_ON_REDIRECT_CODES = %w[301 302 303].freeze

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
      @size_limit = SizeLimit.new(max_bytes)
      @host_guard = HostGuard.new(remote_file.allowed_hosts)
    end

    def call
      size_limit.check!(remote_file.byte_size)
      Transport.new(remote_file: remote_file, size_limit: size_limit, host_guard: host_guard).call
    end

    private

    attr_reader :remote_file, :size_limit, :host_guard
  end
end
