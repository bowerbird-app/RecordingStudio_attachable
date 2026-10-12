# frozen_string_literal: true

require "resolv"

require "test_helper"
require_relative "../lib/recording_studio_attachable/google_drive/client"

class GoogleDriveClientTest < Minitest::Test
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

  def test_list_files_builds_authorized_request_and_escaped_drive_query
    captured = {}
    response = FakeResponse.new(
      body: { "files" => [{ "id" => "file-1" }], "nextPageToken" => "next-page" }.to_json,
      code: "200",
      headers: {},
      success: true
    )

    Net::HTTP.stub(:start, lambda { |host, port, **options, &block|
      captured[:host] = host
      captured[:port] = port
      captured[:use_ssl] = options[:use_ssl]

      http = Object.new
      http.define_singleton_method(:request) do |request|
        captured[:authorization] = request["Authorization"]
        captured[:path] = request.path
        response
      end

      block.call(http)
    }) do
      result = client.list_files(query: "O'Hara", page_token: "page-2", page_size: 10)

      assert_equal [{ "id" => "file-1" }], result.fetch("files")
      assert_equal "next-page", result.fetch("nextPageToken")
    end

    path, query = captured.fetch(:path).split("?", 2)
    params = URI.decode_www_form(query).to_h

    assert_equal "www.googleapis.com", captured[:host]
    assert_equal 443, captured[:port]
    assert_equal true, captured[:use_ssl]
    assert_equal "/drive/v3/files", path
    assert_equal "Bearer access-token", captured[:authorization]
    assert_equal "10", params.fetch("pageSize")
    assert_equal "page-2", params.fetch("pageToken")
    assert_equal "true", params.fetch("supportsAllDrives")
    assert_equal "trashed = false and mimeType != 'application/vnd.google-apps.folder' and name contains 'O\\'Hara'",
                 params.fetch("q")
  end

  def test_download_file_exports_google_workspace_documents_with_expected_extension
    captured = {}
    response = FakeResponse.new(body: "pdf-binary", code: "200", headers: {}, success: true)

    with_public_dns do
      Net::HTTP.stub(:start, lambda { |_host, _port, **options, &block|
        assert_equal true, options[:use_ssl]

        http = stub_http(captured: captured, response: response)
        block.call(http)
      }) do
        result = downloaded(
          "id" => "doc-1",
          "name" => "Project brief",
          "mimeType" => "application/vnd.google-apps.document"
        )

        assert_equal "Project brief.pdf", result.fetch(:filename)
        assert_equal "application/pdf", result.fetch(:content_type)
        assert_equal "pdf-binary", result.fetch(:io).read
      end
    end

    path, query = captured.fetch(:path).split("?", 2)
    params = URI.decode_www_form(query).to_h

    assert_equal "/drive/v3/files/doc-1/export", path
    assert_equal "true", params.fetch("supportsAllDrives")
    assert_equal "application/pdf", params.fetch("mimeType")
  end

  def test_download_file_preserves_existing_export_extension
    response = FakeResponse.new(body: "csv-data", code: "200", headers: {}, success: true)

    with_public_dns do
      Net::HTTP.stub(:start, lambda { |_host, _port, **options, &block|
        assert_equal true, options[:use_ssl]

        http = stub_http(response: response)
        block.call(http)
      }) do
        result = downloaded(
          "id" => "sheet-1",
          "name" => "Report.csv",
          "mimeType" => "application/vnd.google-apps.spreadsheet"
        )

        assert_equal "Report.csv", result.fetch(:filename)
        assert_equal "text/csv", result.fetch(:content_type)
      end
    end
  end

  def test_download_file_uses_normalized_binary_content_type
    captured = {}
    response = FakeResponse.new(
      body: "image-bytes",
      code: "200",
      headers: { "content-type" => "image/png; charset=binary" },
      success: true
    )

    with_public_dns do
      Net::HTTP.stub(:start, lambda { |_host, _port, **options, &block|
        assert_equal true, options[:use_ssl]

        http = stub_http(captured: captured, response: response)
        block.call(http)
      }) do
        result = downloaded(
          "id" => "file-1",
          "name" => "Preview",
          "mimeType" => "application/octet-stream"
        )

        assert_equal "Preview", result.fetch(:filename)
        assert_equal "image/png", result.fetch(:content_type)
        assert_equal "image-bytes", result.fetch(:io).read
      end
    end

    path, query = captured.fetch(:path).split("?", 2)
    params = URI.decode_www_form(query).to_h

    assert_equal "/drive/v3/files/file-1", path
    assert_equal "media", params.fetch("alt")
    assert_equal "true", params.fetch("supportsAllDrives")
  end

  def test_download_file_follows_redirects_for_binary_downloads
    requests = []
    redirect_response = FakeRedirectResponse.new(
      body: "",
      code: "302",
      headers: { "location" => "https://lh3.googleusercontent.com/download/abc" }
    )
    success_response = FakeResponse.new(
      body: "image-bytes",
      code: "200",
      headers: { "content-type" => "image/png" },
      success: true
    )

    with_public_dns do
      Net::HTTP.stub(:start, lambda { |host, _port, **options, &block|
        assert_equal true, options[:use_ssl]

        http = Object.new
        http.define_singleton_method(:request) do |request, &request_block|
          requests << { host: host, path: request.path, authorization: request["Authorization"] }
          response = host == "www.googleapis.com" ? redirect_response : success_response
          request_block ? request_block.call(response) : response
        end
        block.call(http)
      }) do
        result = downloaded(
          "id" => "file-1",
          "name" => "Preview",
          "mimeType" => "application/octet-stream"
        )

        assert_equal "image-bytes", result.fetch(:io).read
        assert_equal "image/png", result.fetch(:content_type)
      end
    end

    assert_equal "www.googleapis.com", requests.first.fetch(:host)
    assert_includes requests.first.fetch(:path), "/drive/v3/files/file-1?"
    assert_equal "Bearer access-token", requests.first.fetch(:authorization)
    assert_equal "lh3.googleusercontent.com", requests.second.fetch(:host)
    assert_equal "/download/abc", requests.second.fetch(:path)
    assert_nil requests.second.fetch(:authorization)
  end

  def test_fetch_file_encodes_file_ids_in_the_request_path
    captured = {}
    response = FakeResponse.new(
      body: { "id" => "file/1", "name" => "Preview", "mimeType" => "image/png" }.to_json,
      code: "200",
      headers: {},
      success: true
    )

    Net::HTTP.stub(:start, lambda { |_host, _port, **options, &block|
      http = Object.new
      http.define_singleton_method(:request) do |request|
        captured[:path] = request.path
        response
      end
      block.call(http)
    }) do
      client.fetch_file("file/1")
    end

    path, _query = captured.fetch(:path).split("?", 2)
    assert_equal "/drive/v3/files/file%2F1", path
  end

  def test_fetch_file_requests_support_for_all_drives
    captured = {}
    response = FakeResponse.new(
      body: { "id" => "file-1", "name" => "Preview", "mimeType" => "image/png" }.to_json,
      code: "200",
      headers: {},
      success: true
    )

    Net::HTTP.stub(:start, lambda { |_host, _port, **options, &block|
      assert_equal true, options[:use_ssl]

      http = Object.new
      http.define_singleton_method(:request) do |request|
        captured[:path] = request.path
        response
      end
      block.call(http)
    }) do
      result = client.fetch_file("file-1")

      assert_equal "file-1", result.fetch("id")
    end

    path, query = captured.fetch(:path).split("?", 2)
    params = URI.decode_www_form(query).to_h

    assert_equal "/drive/v3/files/file-1", path
    assert_equal "true", params.fetch("supportsAllDrives")
    assert_equal "id,name,mimeType,resourceKey,webViewLink,size", params.fetch("fields")
  end

  def test_fetch_file_includes_resource_key_when_picker_provides_one
    captured = {}
    response = FakeResponse.new(
      body: { "id" => "file-1", "name" => "Preview", "mimeType" => "image/png" }.to_json,
      code: "200",
      headers: {},
      success: true
    )

    Net::HTTP.stub(:start, lambda { |_host, _port, **options, &block|
      assert_equal true, options[:use_ssl]

      http = Object.new
      http.define_singleton_method(:request) do |request|
        captured[:path] = request.path
        response
      end
      block.call(http)
    }) do
      client.fetch_file("file-1", resource_key: "resource-key-1")
    end

    _path, query = captured.fetch(:path).split("?", 2)
    params = URI.decode_www_form(query).to_h
    assert_equal "resource-key-1", params.fetch("resourceKey")
  end

  def test_download_file_falls_back_to_metadata_content_type_when_response_header_is_blank
    response = FakeResponse.new(body: "payload", code: "200", headers: { "content-type" => nil }, success: true)

    with_public_dns do
      Net::HTTP.stub(:start, lambda { |_host, _port, **options, &block|
        assert_equal true, options[:use_ssl]
        block.call(stub_http(response: response))
      }) do
        result = downloaded(
          "id" => "file-2",
          "name" => "Raw export",
          "mimeType" => "application/zip"
        )

        assert_equal "application/zip", result.fetch(:content_type)
      end
    end
  end

  def test_download_file_includes_resource_key_in_binary_downloads
    captured = {}
    response = FakeResponse.new(body: "payload", code: "200", headers: { "content-type" => "image/png" }, success: true)

    with_public_dns do
      Net::HTTP.stub(:start, lambda { |_host, _port, **options, &block|
        assert_equal true, options[:use_ssl]
        block.call(stub_http(captured: captured, response: response))
      }) do
        downloaded(
          "id" => "file-2",
          "name" => "Shared image",
          "mimeType" => "image/png",
          "resourceKey" => "resource-key-2"
        )
      end
    end

    _path, query = captured.fetch(:path).split("?", 2)
    params = URI.decode_www_form(query).to_h
    assert_equal "resource-key-2", params.fetch("resourceKey")
  end

  def test_resolve_builds_an_export_remote_file_from_drive_metadata
    response = FakeResponse.new(
      body: {
        "id" => "doc-1",
        "name" => "Project",
        "mimeType" => "application/vnd.google-apps.document",
        "webViewLink" => "https://docs.google.test/doc-1",
        "size" => "12"
      }.to_json,
      code: "200",
      headers: {},
      success: true
    )

    Net::HTTP.stub(:start, lambda { |_host, _port, **_options, &block|
      http = Object.new
      http.define_singleton_method(:request) { |_request| response }
      block.call(http)
    }) do
      remote_file = client.resolve(
        "id" => "doc-1",
        "name" => "Override",
        "description" => "Notes",
        "resource_key" => "rk-1"
      )

      assert_equal "Override.pdf", remote_file.filename
      assert_equal "application/pdf", remote_file.content_type
      assert_equal "doc-1", remote_file.external_id
      assert_equal "Notes", remote_file.description
      assert_includes remote_file.uri.path, "/files/doc-1/export"
      assert_includes remote_file.uri.query, "mimeType=application%2Fpdf"
      assert_includes remote_file.uri.query, "resourceKey=rk-1"
    end
  end

  def test_fetch_file_refuses_a_non_https_host
    error = assert_raises(RecordingStudioAttachable::GoogleDrive::Client::Error) do
      client.send(:perform_get_request, URI("http://www.googleapis.com/drive/v3/files/1"), redirects_remaining: 1)
    end

    assert_equal "Google Drive request must use HTTPS", error.message
  end

  def test_fetch_file_refuses_a_json_host_outside_google_apis
    error = assert_raises(RecordingStudioAttachable::GoogleDrive::Client::Error) do
      client.send(:perform_get_request, URI("https://evil.example.test/files/1"), redirects_remaining: 1)
    end

    assert_equal "Google Drive request host is not allowed", error.message
  end

  def test_fetch_file_refuses_a_cross_host_json_redirect
    redirect = FakeRedirectResponse.new(
      body: "",
      code: "302",
      headers: { "location" => "https://evil.example.test/files/1" }
    )

    Net::HTTP.stub(:start, lambda { |_host, _port, **_options, &block|
      http = Object.new
      http.define_singleton_method(:request) { |_request| redirect }
      block.call(http)
    }) do
      error = assert_raises(RecordingStudioAttachable::GoogleDrive::Client::Error) do
        client.fetch_file("file-1")
      end

      assert_equal "Google Drive request refused a cross-host redirect", error.message
    end
  end

  def test_fetch_file_follows_a_same_host_json_redirect
    redirect = FakeRedirectResponse.new(
      body: "",
      code: "302",
      headers: { "location" => "https://www.googleapis.com/drive/v3/files/file-1?alt=json" }
    )
    success = FakeResponse.new(
      body: { "id" => "file-1", "name" => "Preview" }.to_json,
      code: "200",
      headers: {},
      success: true
    )
    requests = []

    Net::HTTP.stub(:start, lambda { |_host, _port, **_options, &block|
      http = Object.new
      http.define_singleton_method(:request) do |request|
        requests << request.path
        requests.one? ? redirect : success
      end
      block.call(http)
    }) do
      result = client.fetch_file("file-1")

      assert_equal "file-1", result.fetch("id")
    end

    assert_equal 2, requests.size
  end

  def test_fetch_file_raises_when_json_redirects_are_exhausted
    redirect = FakeRedirectResponse.new(
      body: "",
      code: "302",
      headers: { "location" => "/drive/v3/files/file-1" }
    )

    Net::HTTP.stub(:start, lambda { |_host, _port, **_options, &block|
      http = Object.new
      http.define_singleton_method(:request) { |_request| redirect }
      block.call(http)
    }) do
      error = assert_raises(RecordingStudioAttachable::GoogleDrive::Client::Error) do
        client.fetch_file("file-1")
      end

      assert_equal "Google Drive request redirected too many times", error.message
    end
  end

  def test_fetch_file_uses_fallback_when_error_body_is_blank
    response = FakeResponse.new(body: "", code: "503", headers: {}, success: false)

    Net::HTTP.stub(:start, lambda { |_host, _port, **_options, &block|
      http = Object.new
      http.define_singleton_method(:request) { |_request| response }
      block.call(http)
    }) do
      error = assert_raises(RecordingStudioAttachable::GoogleDrive::Client::Error) do
        client.fetch_file("file-1")
      end

      assert_equal "Google Drive request failed (HTTP 503): no response body", error.message
    end
  end

  def test_list_files_raises_unauthorized_error_when_google_rejects_the_token
    response = FakeResponse.new(
      body: { error: { message: "expired" } }.to_json,
      code: "401",
      headers: {},
      success: false
    )

    Net::HTTP.stub(:start, lambda { |_host, _port, **options, &block|
      assert_equal true, options[:use_ssl]

      http = Object.new
      http.define_singleton_method(:request) { |_request| response }
      block.call(http)
    }) do
      error = assert_raises(RecordingStudioAttachable::GoogleDrive::Client::UnauthorizedError) do
        client.list_files
      end

      assert_equal "expired", error.message
    end
  end

  def test_fetch_file_raises_default_error_message_for_non_json_failures
    response = FakeResponse.new(body: "gateway error", code: "502", headers: {}, success: false)

    Net::HTTP.stub(:start, lambda { |_host, _port, **options, &block|
      assert_equal true, options[:use_ssl]

      http = Object.new
      http.define_singleton_method(:request) { |_request| response }
      block.call(http)
    }) do
      error = assert_raises(RecordingStudioAttachable::GoogleDrive::Client::Error) do
        client.fetch_file("file-1")
      end

      assert_equal "Google Drive request failed (HTTP 502): gateway error", error.message
    end
  end

  def test_fetch_file_truncates_long_non_json_failure_bodies
    response = FakeResponse.new(body: "x" * 250, code: "502", headers: {}, success: false)

    Net::HTTP.stub(:start, lambda { |_host, _port, **options, &block|
      assert_equal true, options[:use_ssl]

      http = Object.new
      http.define_singleton_method(:request) { |_request| response }
      block.call(http)
    }) do
      error = assert_raises(RecordingStudioAttachable::GoogleDrive::Client::Error) do
        client.fetch_file("file-1")
      end

      assert_match(/Google Drive request failed \(HTTP 502\): x+\.\.\./, error.message)
      assert_operator error.message.length, :<=, 250
    end
  end

  def test_fetch_file_uses_error_description_for_generic_failures
    response = FakeResponse.new(
      body: { "error_description" => "quota exceeded" }.to_json,
      code: "429",
      headers: {},
      success: false
    )

    Net::HTTP.stub(:start, lambda { |_host, _port, **options, &block|
      assert_equal true, options[:use_ssl]

      http = Object.new
      http.define_singleton_method(:request) { |_request| response }
      block.call(http)
    }) do
      error = assert_raises(RecordingStudioAttachable::GoogleDrive::Client::Error) do
        client.fetch_file("file-1")
      end

      assert_equal "quota exceeded", error.message
    end
  end

  def test_list_files_without_query_only_uses_default_drive_clauses
    captured = {}
    response = FakeResponse.new(body: { "files" => [] }.to_json, code: "200", headers: {}, success: true)

    Net::HTTP.stub(:start, lambda { |_host, _port, **options, &block|
      assert_equal true, options[:use_ssl]

      http = Object.new
      http.define_singleton_method(:request) do |request|
        captured[:path] = request.path
        response
      end
      block.call(http)
    }) do
      client.list_files
    end

    _path, query = captured.fetch(:path).split("?", 2)
    params = URI.decode_www_form(query).to_h
    assert_equal "trashed = false and mimeType != 'application/vnd.google-apps.folder'", params.fetch("q")
  end

  private

  def client
    @client ||= RecordingStudioAttachable::GoogleDrive::Client.new(access_token: "access-token")
  end

  def downloaded(file)
    remote_file = client.remote_file_for(file.stringify_keys)
    fetched = RecordingStudioAttachable::SafeRemoteFetch.call(
      remote_file,
      max_bytes: RecordingStudioAttachable.configuration.max_file_size
    )
    {
      io: fetched.io,
      filename: remote_file.filename,
      content_type: fetched.content_type || remote_file.content_type
    }
  end

  def with_public_dns(&)
    Resolv.stub(:getaddresses, ->(_host) { ["8.8.8.8"] }, &)
  end

  def stub_http(response:, captured: nil)
    http = Object.new
    http.define_singleton_method(:request) do |request, &request_block|
      captured[:path] = request.path if captured
      request_block ? request_block.call(response) : response
    end
    http
  end
end
