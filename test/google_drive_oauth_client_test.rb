# frozen_string_literal: true

require "test_helper"
require_relative "../lib/recording_studio_attachable/google_drive/oauth_client"

class GoogleDriveOAuthClientTest < Minitest::Test
  FakeResponse = Struct.new(:body, :code, :success, keyword_init: true) do
    def is_a?(klass)
      return success if klass == Net::HTTPSuccess

      super
    end
  end

  def test_authorization_url_includes_the_expected_google_parameters
    url = client.authorization_url(state: "state-123")
    uri = URI.parse(url)
    params = URI.decode_www_form(uri.query).to_h

    assert_equal RecordingStudioAttachable::GoogleDrive::OAuthClient::AUTHORIZATION_ENDPOINT, "#{uri.scheme}://#{uri.host}#{uri.path}"
    assert_equal "client-id", params.fetch("client_id")
    assert_equal "state-123", params.fetch("state")
    assert_equal "offline", params.fetch("access_type")
    assert_equal "true", params.fetch("include_granted_scopes")
    assert_equal "consent", params.fetch("prompt")
    assert_equal "code", params.fetch("response_type")
    assert_equal "https://example.test/oauth/callback", params.fetch("redirect_uri")
    assert_equal "scope-1 scope-2", params.fetch("scope")
  end

  def test_authorization_url_requires_a_configured_google_drive_client
    unconfigured = RecordingStudioAttachable::Configuration::GoogleDriveConfiguration.new
    oauth_client = RecordingStudioAttachable::GoogleDrive::OAuthClient.new(configuration: unconfigured)

    error = assert_raises(RecordingStudioAttachable::DependencyUnavailableError) do
      oauth_client.authorization_url(state: "missing")
    end

    assert_equal "Google Drive addon is missing client credentials or redirect URI", error.message
  end

  def test_exchange_code_posts_form_data_and_normalizes_token_expiry
    captured_body = nil
    response = FakeResponse.new(
      body: { "access_token" => "token-1", "refresh_token" => "refresh-1", "expires_in" => 120 }.to_json,
      code: "200",
      success: true
    )

    Net::HTTP.stub(:start, lambda { |host, port, use_ssl:, &block|
      assert_equal "oauth2.googleapis.com", host
      assert_equal 443, port
      assert_equal true, use_ssl

      http = Object.new
      http.define_singleton_method(:request) do |request|
        captured_body = URI.decode_www_form(request.body).to_h
        response
      end

      block.call(http)
    }) do
      Time.stub(:current, Time.at(1_700_000_000)) do
        result = client.exchange_code(code: "auth-code")

        assert_equal "token-1", result.fetch("access_token")
        assert_equal "refresh-1", result.fetch("refresh_token")
        assert_equal 1_700_000_120, result.fetch("expires_at")
      end
    end

    assert_equal "client-id", captured_body.fetch("client_id")
    assert_equal "client-secret", captured_body.fetch("client_secret")
    assert_equal "auth-code", captured_body.fetch("code")
    assert_equal "authorization_code", captured_body.fetch("grant_type")
    assert_equal "https://example.test/oauth/callback", captured_body.fetch("redirect_uri")
  end

  def test_refresh_token_keeps_response_when_expiration_is_not_positive
    response = FakeResponse.new(
      body: { "access_token" => "token-2", "expires_in" => 0 }.to_json,
      code: "200",
      success: true
    )

    Net::HTTP.stub(:start, lambda { |_host, _port, use_ssl:, &block|
      assert_equal true, use_ssl

      http = Object.new
      http.define_singleton_method(:request) { |_request| response }
      block.call(http)
    }) do
      result = client.refresh_token(refresh_token: "refresh-1")

      assert_equal({ "access_token" => "token-2", "expires_in" => 0 }, result)
    end
  end

  def test_exchange_code_raises_service_error_with_google_description
    response = FakeResponse.new(
      body: { "error_description" => "bad code" }.to_json,
      code: "400",
      success: false
    )

    Net::HTTP.stub(:start, lambda { |_host, _port, use_ssl:, &block|
      assert_equal true, use_ssl

      http = Object.new
      http.define_singleton_method(:request) { |_request| response }
      block.call(http)
    }) do
      error = assert_raises(RecordingStudioAttachable::GoogleDrive::OAuthClient::Error) do
        client.exchange_code(code: "bad-code")
      end

      assert_equal "bad code", error.message
    end
  end

  def test_refresh_token_uses_default_error_message_for_invalid_json_failures
    response = FakeResponse.new(body: "upstream failure", code: "502", success: false)

    Net::HTTP.stub(:start, lambda { |_host, _port, use_ssl:, &block|
      assert_equal true, use_ssl

      http = Object.new
      http.define_singleton_method(:request) { |_request| response }
      block.call(http)
    }) do
      error = assert_raises(RecordingStudioAttachable::GoogleDrive::OAuthClient::Error) do
        client.refresh_token(refresh_token: "refresh-1")
      end

      assert_equal "Google Drive authentication failed", error.message
    end
  end

  def test_exchange_code_uses_error_field_when_error_description_is_missing
    response = FakeResponse.new(
      body: { "error" => "invalid_grant" }.to_json,
      code: "400",
      success: false
    )

    Net::HTTP.stub(:start, lambda { |_host, _port, use_ssl:, &block|
      assert_equal true, use_ssl

      http = Object.new
      http.define_singleton_method(:request) { |_request| response }
      block.call(http)
    }) do
      error = assert_raises(RecordingStudioAttachable::GoogleDrive::OAuthClient::Error) do
        client.exchange_code(code: "bad-code")
      end

      assert_equal "invalid_grant", error.message
    end
  end

  private

  def client
    @client ||= RecordingStudioAttachable::GoogleDrive::OAuthClient.new(configuration: configured_google_drive)
  end

  def configured_google_drive
    @configured_google_drive ||= RecordingStudioAttachable::Configuration::GoogleDriveConfiguration.new.tap do |configuration|
      configuration.merge!(
        client_id: "client-id",
        client_secret: "client-secret",
        redirect_uri: "https://example.test/oauth/callback",
        scopes: %w[scope-1 scope-2]
      )
    end
  end
end
