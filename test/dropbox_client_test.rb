# frozen_string_literal: true

require "test_helper"

class DropboxClientTest < Minitest::Test
  FakeResponse = Struct.new(:body, :code, :headers, :success, keyword_init: true) do
    delegate :[], to: :headers

    def is_a?(klass)
      return success if klass == Net::HTTPSuccess

      super
    end
  end

  def test_resolve_loads_metadata_by_id_and_builds_a_download_descriptor
    captured = {}
    response = FakeResponse.new(
      body: { "id" => "id:file-1", "name" => "Brief.pdf", "size" => 12, ".tag" => "file" }.to_json,
      code: "200",
      headers: {},
      success: true
    )

    Net::HTTP.stub(:start, lambda { |host, _port, **options, &block|
      captured[:host] = host
      http = Object.new
      http.define_singleton_method(:request) do |request|
        captured[:authorization] = request["Authorization"]
        captured[:body] = JSON.parse(request.body)
        captured[:path] = request.path
        response
      end
      block.call(http)
    }) do
      remote_file = client.resolve("id" => "file-1")

      assert_equal URI("https://content.dropboxapi.com/2/files/download"), remote_file.uri
      assert_equal "POST", remote_file.http_method
      assert_equal "Brief.pdf", remote_file.filename
      assert_equal "id:file-1", remote_file.external_id
      assert_equal({ "path" => "id:file-1" }.to_json, remote_file.headers.fetch("Dropbox-API-Arg"))
    end

    assert_equal "api.dropboxapi.com", captured[:host]
    assert_equal "/2/files/get_metadata", captured[:path]
    assert_equal({ "path" => "id:file-1" }, captured[:body])
    assert_equal "Bearer access-token", captured[:authorization]
  end

  def test_resolve_rejects_client_supplied_urls
    error = assert_raises(RecordingStudioAttachable::Dropbox::Client::Error) do
      client.resolve("url" => "https://dl.dropboxusercontent.com/s/stolen")
    end

    assert_equal "Dropbox imports require a file id from the Dropbox API", error.message
  end

  def test_resolve_rejects_url_shaped_ids
    error = assert_raises(RecordingStudioAttachable::Dropbox::Client::Error) do
      client.resolve("id" => "https://dl.dropboxusercontent.com/s/stolen")
    end

    assert_equal "Dropbox imports require a file id from the Dropbox API", error.message
  end

  def test_resolve_rejects_folders
    response = FakeResponse.new(
      body: { "id" => "id:folder-1", "name" => "Docs", ".tag" => "folder" }.to_json,
      code: "200",
      headers: {},
      success: true
    )

    Net::HTTP.stub(:start, lambda { |_host, _port, **options, &block|
      http = Object.new
      http.define_singleton_method(:request) { |_request| response }
      block.call(http)
    }) do
      error = assert_raises(RecordingStudioAttachable::Dropbox::Client::Error) do
        client.resolve("id" => "folder-1")
      end

      assert_equal "Dropbox folders cannot be imported", error.message
    end
  end

  def test_resolve_rejects_a_blank_file_id
    error = assert_raises(RecordingStudioAttachable::Dropbox::Client::Error) do
      client.resolve({})
    end

    assert_equal "Select a Dropbox file to import", error.message
  end

  def test_resolve_keeps_an_id_prefixed_path_and_selection_overrides
    response = FakeResponse.new(
      body: { "name" => "Brief.pdf", "size" => 12, ".tag" => "file" }.to_json,
      code: "200",
      headers: {},
      success: true
    )
    captured = {}

    Net::HTTP.stub(:start, lambda { |_host, _port, **_options, &block|
      http = Object.new
      http.define_singleton_method(:request) do |request|
        captured[:body] = JSON.parse(request.body)
        response
      end
      block.call(http)
    }) do
      remote_file = client.resolve(
        "id" => "id:file-1",
        "name" => "Override",
        "description" => "From Dropbox"
      )

      assert_equal "Override", remote_file.name
      assert_equal "From Dropbox", remote_file.description
      assert_equal "id:file-1", remote_file.external_id
      assert_equal "application/octet-stream", remote_file.content_type
    end

    assert_equal({ "path" => "id:file-1" }, captured.fetch(:body))
  end

  def test_resolve_raises_unauthorized_error_on_401
    response = FakeResponse.new(
      body: { "error_summary" => "expired_access_token/" }.to_json,
      code: "401",
      headers: {},
      success: false
    )

    Net::HTTP.stub(:start, lambda { |_host, _port, **_options, &block|
      http = Object.new
      http.define_singleton_method(:request) { |_request| response }
      block.call(http)
    }) do
      error = assert_raises(RecordingStudioAttachable::Dropbox::Client::UnauthorizedError) do
        client.resolve("id" => "file-1")
      end

      assert_equal "expired_access_token/", error.message
    end
  end

  def test_resolve_uses_dropbox_error_tag_for_api_failures
    response = FakeResponse.new(
      body: { "error" => { ".tag" => "path/not_found" } }.to_json,
      code: "409",
      headers: {},
      success: false
    )

    Net::HTTP.stub(:start, lambda { |_host, _port, **_options, &block|
      http = Object.new
      http.define_singleton_method(:request) { |_request| response }
      block.call(http)
    }) do
      error = assert_raises(RecordingStudioAttachable::Dropbox::Client::Error) do
        client.resolve("id" => "file-1")
      end

      assert_equal "path/not_found", error.message
    end
  end

  def test_resolve_uses_fallback_message_for_empty_non_json_failures
    response = FakeResponse.new(body: "", code: "500", headers: {}, success: false)

    Net::HTTP.stub(:start, lambda { |_host, _port, **_options, &block|
      http = Object.new
      http.define_singleton_method(:request) { |_request| response }
      block.call(http)
    }) do
      error = assert_raises(RecordingStudioAttachable::Dropbox::Client::Error) do
        client.resolve("id" => "file-1")
      end

      assert_equal "Dropbox request failed (HTTP 500): no response body", error.message
    end
  end

  def test_resolve_uses_response_body_snippet_when_json_is_invalid
    response = FakeResponse.new(body: "gateway timeout", code: "504", headers: {}, success: false)

    Net::HTTP.stub(:start, lambda { |_host, _port, **_options, &block|
      http = Object.new
      http.define_singleton_method(:request) { |_request| response }
      block.call(http)
    }) do
      error = assert_raises(RecordingStudioAttachable::Dropbox::Client::Error) do
        client.resolve("id" => "file-1")
      end

      assert_equal "Dropbox request failed (HTTP 504): gateway timeout", error.message
    end
  end

  def test_resolve_ignores_urls_when_an_id_is_present
    response = FakeResponse.new(
      body: { "id" => "id:file-1", "name" => "Brief.pdf", "size" => 12, ".tag" => "file" }.to_json,
      code: "200",
      headers: {},
      success: true
    )

    Net::HTTP.stub(:start, lambda { |_host, _port, **options, &block|
      http = Object.new
      http.define_singleton_method(:request) { |_request| response }
      block.call(http)
    }) do
      remote_file = client.resolve("id" => "file-1", "url" => "https://dl.dropboxusercontent.com/s/stolen")

      assert_equal "id:file-1", remote_file.external_id
      assert_not_includes remote_file.uri.to_s, "dl.dropboxusercontent.com"
    end
  end

  private

  def client
    @client ||= RecordingStudioAttachable::Dropbox::Client.new(access_token: "access-token")
  end
end
