# frozen_string_literal: true

require "test_helper"
require_relative "../lib/recording_studio_attachable/google_drive/client"

class GoogleDriveClientTest < Minitest::Test
  FakeResponse = Struct.new(:body, :code, :headers, :success, keyword_init: true) do
    def [](key)
      headers[key]
    end

    def is_a?(klass)
      return success if klass == Net::HTTPSuccess

      super
    end
  end

  FakeRedirectResponse = Struct.new(:body, :code, :headers, keyword_init: true) do
    def [](key)
      headers[key]
    end

    def is_a?(klass)
      return true if klass == Net::HTTPRedirection

      super
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

    Net::HTTP.stub(:start, lambda { |host, port, use_ssl:, &block|
      captured[:host] = host
      captured[:port] = port
      captured[:use_ssl] = use_ssl

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

    Net::HTTP.stub(:start, lambda { |_host, _port, use_ssl:, &block|
      assert_equal true, use_ssl

      http = Object.new
      http.define_singleton_method(:request) do |request|
        captured[:path] = request.path
        response
      end
      block.call(http)
    }) do
      result = client.download_file(
        "id" => "doc-1",
        "name" => "Project brief",
        "mimeType" => "application/vnd.google-apps.document"
      )

      assert_equal "Project brief.pdf", result.fetch(:filename)
      assert_equal "application/pdf", result.fetch(:content_type)
      assert_equal "pdf-binary", result.fetch(:io).read
    end

    path, query = captured.fetch(:path).split("?", 2)
    params = URI.decode_www_form(query).to_h

    assert_equal "/drive/v3/files/doc-1/export", path
    assert_equal "true", params.fetch("supportsAllDrives")
    assert_equal "application/pdf", params.fetch("mimeType")
  end

  def test_download_file_preserves_existing_export_extension
    response = FakeResponse.new(body: "csv-data", code: "200", headers: {}, success: true)

    Net::HTTP.stub(:start, lambda { |_host, _port, use_ssl:, &block|
      assert_equal true, use_ssl

      http = Object.new
      http.define_singleton_method(:request) { |_request| response }
      block.call(http)
    }) do
      result = client.download_file(
        "id" => "sheet-1",
        "name" => "Report.csv",
        "mimeType" => "application/vnd.google-apps.spreadsheet"
      )

      assert_equal "Report.csv", result.fetch(:filename)
      assert_equal "text/csv", result.fetch(:content_type)
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

    Net::HTTP.stub(:start, lambda { |_host, _port, use_ssl:, &block|
      assert_equal true, use_ssl

      http = Object.new
      http.define_singleton_method(:request) do |request|
        captured[:path] = request.path
        response
      end
      block.call(http)
    }) do
      result = client.download_file(
        "id" => "file-1",
        "name" => "Preview",
        "mimeType" => "application/octet-stream"
      )

      assert_equal "Preview", result.fetch(:filename)
      assert_equal "image/png", result.fetch(:content_type)
      assert_equal "image-bytes", result.fetch(:io).read
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
      headers: { "location" => "https://files.example.test/download/abc" }
    )
    success_response = FakeResponse.new(
      body: "image-bytes",
      code: "200",
      headers: { "content-type" => "image/png" },
      success: true
    )

    Net::HTTP.stub(:start, lambda { |host, _port, use_ssl:, &block|
      assert_equal true, use_ssl

      http = Object.new
      http.define_singleton_method(:request) do |request|
        requests << { host: host, path: request.path, authorization: request["Authorization"] }
        host == "www.googleapis.com" ? redirect_response : success_response
      end
      block.call(http)
    }) do
      result = client.download_file(
        "id" => "file-1",
        "name" => "Preview",
        "mimeType" => "application/octet-stream"
      )

      assert_equal "image-bytes", result.fetch(:io).read
      assert_equal "image/png", result.fetch(:content_type)
    end

    assert_equal "www.googleapis.com", requests.first.fetch(:host)
    assert_includes requests.first.fetch(:path), "/drive/v3/files/file-1?"
    assert_equal "files.example.test", requests.second.fetch(:host)
    assert_equal "/download/abc", requests.second.fetch(:path)
  end

  def test_fetch_file_requests_support_for_all_drives
    captured = {}
    response = FakeResponse.new(
      body: { "id" => "file-1", "name" => "Preview", "mimeType" => "image/png" }.to_json,
      code: "200",
      headers: {},
      success: true
    )

    Net::HTTP.stub(:start, lambda { |_host, _port, use_ssl:, &block|
      assert_equal true, use_ssl

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
    assert_equal "id,name,mimeType,resourceKey,webViewLink", params.fetch("fields")
  end

  def test_fetch_file_includes_resource_key_when_picker_provides_one
    captured = {}
    response = FakeResponse.new(
      body: { "id" => "file-1", "name" => "Preview", "mimeType" => "image/png" }.to_json,
      code: "200",
      headers: {},
      success: true
    )

    Net::HTTP.stub(:start, lambda { |_host, _port, use_ssl:, &block|
      assert_equal true, use_ssl

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

    Net::HTTP.stub(:start, lambda { |_host, _port, use_ssl:, &block|
      assert_equal true, use_ssl

      http = Object.new
      http.define_singleton_method(:request) { |_request| response }
      block.call(http)
    }) do
      result = client.download_file(
        "id" => "file-2",
        "name" => "Raw export",
        "mimeType" => "application/zip"
      )

      assert_equal "application/zip", result.fetch(:content_type)
    end
  end

  def test_download_file_includes_resource_key_in_binary_downloads
    captured = {}
    response = FakeResponse.new(body: "payload", code: "200", headers: { "content-type" => "image/png" }, success: true)

    Net::HTTP.stub(:start, lambda { |_host, _port, use_ssl:, &block|
      assert_equal true, use_ssl

      http = Object.new
      http.define_singleton_method(:request) do |request|
        captured[:path] = request.path
        response
      end
      block.call(http)
    }) do
      client.download_file(
        "id" => "file-2",
        "name" => "Shared image",
        "mimeType" => "image/png",
        "resourceKey" => "resource-key-2"
      )
    end

    _path, query = captured.fetch(:path).split("?", 2)
    params = URI.decode_www_form(query).to_h
    assert_equal "resource-key-2", params.fetch("resourceKey")
  end

  def test_list_files_raises_unauthorized_error_when_google_rejects_the_token
    response = FakeResponse.new(
      body: { error: { message: "expired" } }.to_json,
      code: "401",
      headers: {},
      success: false
    )

    Net::HTTP.stub(:start, lambda { |_host, _port, use_ssl:, &block|
      assert_equal true, use_ssl

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

    Net::HTTP.stub(:start, lambda { |_host, _port, use_ssl:, &block|
      assert_equal true, use_ssl

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

    Net::HTTP.stub(:start, lambda { |_host, _port, use_ssl:, &block|
      assert_equal true, use_ssl

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

    Net::HTTP.stub(:start, lambda { |_host, _port, use_ssl:, &block|
      assert_equal true, use_ssl

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

    Net::HTTP.stub(:start, lambda { |_host, _port, use_ssl:, &block|
      assert_equal true, use_ssl

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
end
