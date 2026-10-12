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

    Net::HTTP.stub(:start, lambda { |host, _port, use_ssl:, &block|
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

    Net::HTTP.stub(:start, lambda { |_host, _port, use_ssl:, &block|
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

  def test_resolve_ignores_urls_when_an_id_is_present
    response = FakeResponse.new(
      body: { "id" => "id:file-1", "name" => "Brief.pdf", "size" => 12, ".tag" => "file" }.to_json,
      code: "200",
      headers: {},
      success: true
    )

    Net::HTTP.stub(:start, lambda { |_host, _port, use_ssl:, &block|
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
