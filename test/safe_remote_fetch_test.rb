# frozen_string_literal: true

require "test_helper"

class SafeRemoteFetchTest < Minitest::Test
  FakeResponse = Struct.new(:body, :code, :headers, :success, keyword_init: true) do
    delegate :[], to: :headers

    def is_a?(klass)
      return success if klass == Net::HTTPSuccess

      super
    end

    def read_body
      yield body.to_s if block_given?
      body
    end
  end

  FakeRedirectResponse = Struct.new(:body, :code, :headers, keyword_init: true) do
    delegate :[], to: :headers

    def is_a?(klass)
      return true if klass == Net::HTTPRedirection

      super
    end

    def read_body
      yield body.to_s if block_given?
      body
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

  def test_cross_host_redirect_drops_authorization_case_insensitively
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
          headers: { "authorization" => "Bearer secret" },
          allowed_hosts: ["api.example.test", "cdn.example.test"]
        )

        assert_equal "bytes", result.io.read
      end
    end

    assert_equal "Bearer secret", requests.first.fetch(:authorization)
    assert_nil requests.second.fetch(:authorization)
  end

  def test_redirect_to_disallowed_host_is_refused
    redirect = FakeRedirectResponse.new(
      body: "",
      code: "302",
      headers: { "location" => "https://evil.example.test/file" }
    )

    with_public_dns do
      stub_http(->(_host, _request) { redirect }) do
        error = assert_raises(RecordingStudioAttachable::SafeRemoteFetch::Error) do
          fetch(uri: "https://api.example.test/file", allowed_hosts: ["api.example.test"])
        end

        assert_equal "Remote download host is not allowed", error.message
      end
    end
  end

  def test_redirect_to_host_resolving_to_private_ip_is_refused
    redirect = FakeRedirectResponse.new(
      body: "",
      code: "302",
      headers: { "location" => "https://cdn.example.test/file" }
    )
    addresses = {
      "api.example.test" => ["8.8.8.8"],
      "cdn.example.test" => ["127.0.0.1"]
    }

    Resolv.stub(:getaddresses, ->(host) { addresses.fetch(host) }) do
      stub_http(->(_host, _request) { redirect }) do
        error = assert_raises(RecordingStudioAttachable::SafeRemoteFetch::Error) do
          fetch(
            uri: "https://api.example.test/file",
            allowed_hosts: ["api.example.test", "cdn.example.test"]
          )
        end

        assert_equal "Remote download host resolves to a private address", error.message
      end
    end
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

  def test_cgnat_address_is_refused
    Resolv.stub(:getaddresses, ->(_host) { ["100.64.0.1"] }) do
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

  def test_nil_max_bytes_skips_the_size_cap_and_still_enforces_the_deadline
    ticks = [0.0, 0.1, 61.0]
    response = StreamingResponse.new(chunks: %w[aaaa bbbb], content_type: "text/plain")

    with_public_dns do
      stub_http(->(_host, _request) { response }) do
        Process.stub(:clock_gettime, ->(*) { ticks.shift || 61.0 }) do
          error = assert_raises(RecordingStudioAttachable::SafeRemoteFetch::Error) do
            fetch(uri: "https://api.example.test/file", allowed_hosts: ["api.example.test"], max_bytes: nil)
          end

          assert_equal "Remote download timed out", error.message
        end
      end
    end
  end

  def test_nil_max_bytes_downloads_a_file_that_would_exceed_a_numeric_cap
    response = StreamingResponse.new(chunks: ["x" * 50], content_type: "text/plain", content_length: "50")

    with_public_dns do
      stub_http(->(_host, _request) { response }) do
        result = fetch(uri: "https://api.example.test/file", allowed_hosts: ["api.example.test"], max_bytes: nil)

        assert_equal 50, result.byte_size
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

  def test_start_passes_timeouts_and_validated_ip_before_connect
    captured = {}
    success = FakeResponse.new(body: "bytes", code: "200", headers: {}, success: true)

    with_public_dns do
      stub_http(->(_host, _request) { success }, captured_start: captured) do
        fetch(uri: "https://api.example.test/file", allowed_hosts: ["api.example.test"])
      end
    end

    assert_equal true, captured[:use_ssl]
    assert_equal RecordingStudioAttachable::SafeRemoteFetch::OPEN_TIMEOUT, captured[:open_timeout]
    assert_equal RecordingStudioAttachable::SafeRemoteFetch::READ_TIMEOUT, captured[:read_timeout]
    assert_equal RecordingStudioAttachable::SafeRemoteFetch::SSL_TIMEOUT, captured[:ssl_timeout]
    assert_equal RecordingStudioAttachable::SafeRemoteFetch::WRITE_TIMEOUT, captured[:write_timeout]
    assert_equal "8.8.8.8", captured[:ipaddr]
  end

  def test_overall_deadline_stops_a_trickling_download
    ticks = [0.0, 0.1, 61.0]
    response = StreamingResponse.new(chunks: %w[aaaa bbbb], content_type: "text/plain")

    with_public_dns do
      stub_http(->(_host, _request) { response }) do
        Process.stub(:clock_gettime, ->(*) { ticks.shift || 61.0 }) do
          error = assert_raises(RecordingStudioAttachable::SafeRemoteFetch::Error) do
            fetch(uri: "https://api.example.test/file", allowed_hosts: ["api.example.test"])
          end

          assert_equal "Remote download timed out", error.message
        end
      end
    end
  end

  def test_post_redirect_302_follows_as_get_without_body
    requests = []
    redirect = FakeRedirectResponse.new(
      body: "",
      code: "302",
      headers: { "location" => "https://api.example.test/download" }
    )
    success = FakeResponse.new(body: "bytes", code: "200", headers: {}, success: true)

    with_public_dns do
      stub_http(lambda { |_host, request|
        requests << { method: request.method, body: request.body }
        request.path.include?("/start") ? redirect : success
      }) do
        fetch(
          uri: "https://api.example.test/start",
          allowed_hosts: ["api.example.test"],
          http_method: :post,
          body: "dropbox-arg"
        )
      end
    end

    assert_equal "POST", requests.first.fetch(:method)
    assert_equal "dropbox-arg", requests.first.fetch(:body)
    assert_equal "GET", requests.second.fetch(:method)
    assert_nil requests.second.fetch(:body)
  end

  def test_post_redirect_307_is_refused
    redirect = FakeRedirectResponse.new(
      body: "",
      code: "307",
      headers: { "location" => "https://api.example.test/download" }
    )

    with_public_dns do
      stub_http(->(_host, _request) { redirect }) do
        error = assert_raises(RecordingStudioAttachable::SafeRemoteFetch::Error) do
          fetch(
            uri: "https://api.example.test/start",
            allowed_hosts: ["api.example.test"],
            http_method: :post,
            body: "dropbox-arg"
          )
        end

        assert_equal "Remote download redirected a write request", error.message
      end
    end
  end

  private

  def fetch(**attributes)
    max_bytes = attributes.key?(:max_bytes) ? attributes[:max_bytes] : 100
    remote_file = RecordingStudioAttachable::RemoteFile.new(
      uri: attributes.fetch(:uri),
      allowed_hosts: attributes.fetch(:allowed_hosts),
      headers: attributes.fetch(:headers, {}),
      filename: "file.pdf",
      content_type: "application/pdf",
      byte_size: attributes[:byte_size],
      http_method: attributes.fetch(:http_method, :get),
      body: attributes[:body]
    )
    RecordingStudioAttachable::SafeRemoteFetch.call(remote_file, max_bytes: max_bytes)
  end

  def with_public_dns(&)
    Resolv.stub(:getaddresses, ->(_host) { ["8.8.8.8"] }, &)
  end

  def stub_http(responder, captured_start: nil, &)
    Net::HTTP.stub(:start, lambda { |host, _port, **options, &http_block|
      captured_start&.replace(options)
      assert_equal true, options[:use_ssl]
      http = Object.new
      http.define_singleton_method(:request) do |request, &request_block|
        response = responder.call(host, request)
        request_block ? request_block.call(response) : response
      end
      http_block.call(http)
    }, &)
  end
end
