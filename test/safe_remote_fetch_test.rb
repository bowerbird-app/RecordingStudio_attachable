# frozen_string_literal: true

require "test_helper"

class SafeRemoteFetchTest < Minitest::Test
  FakeResponse = Struct.new(:body, :code, :headers, :success, keyword_init: true) do
    delegate :[], to: :headers

    def is_a?(klass)
      return success if klass == Net::HTTPSuccess

      super
    end
  end

  FakeRedirectResponse = Struct.new(:body, :code, :headers, keyword_init: true) do
    delegate :[], to: :headers

    def is_a?(klass)
      return true if klass == Net::HTTPRedirection

      super
    end
  end

  class StreamingResponse
    def initialize(chunks:, content_length: nil, content_type: "application/pdf")
      @chunks = chunks
      @content_length = content_length
      @content_type = content_type
    end

    def is_a?(klass)
      klass == Net::HTTPSuccess
    end

    def [](header)
      case header
      when "content-length" then @content_length
      when "content-type" then @content_type
      end
    end

    def code
      "200"
    end

    def read_body(&)
      @chunks.each(&)
    end
  end

  def test_cross_host_redirect_drops_authorization
    requests = []
    redirect = FakeRedirectResponse.new(
      body: "",
      code: "302",
      headers: { "location" => "https://cdn.example.test/file" }
    )
    success = FakeResponse.new(body: "bytes", code: "200", headers: { "content-type" => "application/pdf" }, success: true)

    with_public_dns do
      stub_http(lambda { |host, request|
        requests << { host: host, authorization: request["Authorization"] }
        host == "api.example.test" ? redirect : success
      }) do
        result = fetch(
          uri: "https://api.example.test/files/1",
          headers: { "Authorization" => "Bearer secret" },
          allowed_hosts: ["api.example.test", "cdn.example.test"]
        )

        assert_equal "bytes", result.io.read
      end
    end

    assert_equal "Bearer secret", requests.first.fetch(:authorization)
    assert_nil requests.second.fetch(:authorization)
  end

  def test_disallowed_host_is_refused
    error = assert_raises(RecordingStudioAttachable::SafeRemoteFetch::Error) do
      fetch(uri: "https://evil.example.test/file", allowed_hosts: ["api.example.test"])
    end

    assert_equal "Remote download host is not allowed", error.message
  end

  def test_private_ip_is_refused
    Resolv.stub(:getaddresses, ->(_host) { ["127.0.0.1"] }) do
      error = assert_raises(RecordingStudioAttachable::SafeRemoteFetch::Error) do
        fetch(uri: "https://api.example.test/file", allowed_hosts: ["api.example.test"])
      end

      assert_equal "Remote download host resolves to a private address", error.message
    end
  end

  def test_localhost_is_refused
    error = assert_raises(RecordingStudioAttachable::SafeRemoteFetch::Error) do
      fetch(uri: "https://localhost/file", allowed_hosts: ["localhost"])
    end

    assert_equal "Remote download host is not allowed", error.message
  end

  def test_non_443_port_is_refused
    error = assert_raises(RecordingStudioAttachable::SafeRemoteFetch::Error) do
      fetch(uri: "https://api.example.test:8443/file", allowed_hosts: ["api.example.test"])
    end

    assert_equal "Remote download must use port 443", error.message
  end

  def test_http_is_refused
    error = assert_raises(RecordingStudioAttachable::SafeRemoteFetch::Error) do
      fetch(uri: "http://api.example.test/file", allowed_hosts: ["api.example.test"])
    end

    assert_equal "Remote download must use HTTPS", error.message
  end

  def test_oversize_content_length_is_refused_before_body
    read = false
    response = Object.new
    response.define_singleton_method(:is_a?) { |klass| klass == Net::HTTPSuccess }
    response.define_singleton_method(:[]) { |header| header == "content-length" ? "50" : nil }
    response.define_singleton_method(:code) { "200" }
    response.define_singleton_method(:read_body) do |&block|
      read = true
      block.call("x" * 50)
    end

    with_public_dns do
      stub_http(->(_host, _request) { response }) do
        error = assert_raises(RecordingStudioAttachable::SafeRemoteFetch::Error) do
          fetch(uri: "https://api.example.test/file", allowed_hosts: ["api.example.test"], max_bytes: 10)
        end

        assert_equal "Remote file exceeds maximum file size", error.message
        assert_not read
      end
    end
  end

  def test_declared_byte_size_is_refused_before_request
    started = false
    Net::HTTP.stub(:start, lambda { |*|
      started = true
      raise "should not connect"
    }) do
      error = assert_raises(RecordingStudioAttachable::SafeRemoteFetch::Error) do
        fetch(
          uri: "https://api.example.test/file",
          allowed_hosts: ["api.example.test"],
          byte_size: 100,
          max_bytes: 10
        )
      end

      assert_equal "Remote file exceeds maximum file size", error.message
      assert_not started
    end
  end

  def test_byte_cap_stops_a_streaming_download
    response = StreamingResponse.new(chunks: %w[aaaa bbbb cccc], content_type: "text/plain")

    with_public_dns do
      stub_http(->(_host, _request) { response }) do
        error = assert_raises(RecordingStudioAttachable::SafeRemoteFetch::Error) do
          fetch(uri: "https://api.example.test/file", allowed_hosts: ["api.example.test"], max_bytes: 6)
        end

        assert_equal "Remote file exceeds maximum file size", error.message
      end
    end
  end

  private

  def fetch(uri:, allowed_hosts:, headers: {}, max_bytes: 100, byte_size: nil)
    remote_file = RecordingStudioAttachable::RemoteFile.new(
      uri: uri,
      allowed_hosts: allowed_hosts,
      headers: headers,
      filename: "file.pdf",
      content_type: "application/pdf",
      byte_size: byte_size
    )
    RecordingStudioAttachable::SafeRemoteFetch.call(remote_file, max_bytes: max_bytes)
  end

  def with_public_dns(&)
    Resolv.stub(:getaddresses, ->(_host) { ["8.8.8.8"] }, &)
  end

  def stub_http(responder, &)
    Net::HTTP.stub(:start, lambda { |host, _port, use_ssl:, &http_block|
      assert_equal true, use_ssl
      http = Object.new
      http.define_singleton_method(:request) do |request, &request_block|
        response = responder.call(host, request)
        request_block ? request_block.call(response) : response
      end
      http_block.call(http)
    }, &)
  end
end
