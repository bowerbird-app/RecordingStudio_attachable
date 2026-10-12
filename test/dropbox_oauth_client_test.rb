# frozen_string_literal: true

require "test_helper"

class DropboxOAuthClientTest < Minitest::Test
  FakeResponse = Struct.new(:body, :code, :success, keyword_init: true) do
    def is_a?(klass)
      return success if klass == Net::HTTPSuccess

      super
    end
  end

  def test_authorization_url_includes_pkce_and_dropbox_scopes
    verifier = "a" * 43
    challenge = RecordingStudioAttachable::Dropbox::OAuthClient.code_challenge(verifier)
    url = client.authorization_url(state: "state-123", code_challenge: challenge)
    uri = URI.parse(url)
    params = URI.decode_www_form(uri.query).to_h

    assert_equal RecordingStudioAttachable::Dropbox::OAuthClient::AUTHORIZATION_ENDPOINT, "#{uri.scheme}://#{uri.host}#{uri.path}"
    assert_equal "client-id", params.fetch("client_id")
    assert_equal "state-123", params.fetch("state")
    assert_equal "code", params.fetch("response_type")
    assert_equal "S256", params.fetch("code_challenge_method")
    assert_equal challenge, params.fetch("code_challenge")
    assert_equal "offline", params.fetch("token_access_type")
    assert_equal "files.metadata.read files.content.read", params.fetch("scope")
  end

  def test_code_challenge_is_s256_base64url_without_padding
    verifier = "abc"
    digest = Digest::SHA256.digest(verifier)
    assert_equal Base64.urlsafe_encode64(digest, padding: false),
                 RecordingStudioAttachable::Dropbox::OAuthClient.code_challenge(verifier)
  end

  def test_exchange_code_posts_pkce_verifier
    captured_body = nil
    response = FakeResponse.new(
      body: { "access_token" => "token-1", "refresh_token" => "refresh-1", "expires_in" => 120 }.to_json,
      code: "200",
      success: true
    )

    Net::HTTP.stub(:start, lambda { |host, port, **options, &block|
      assert_equal "api.dropboxapi.com", host
      assert_equal 443, port
      assert_equal true, options[:use_ssl]
      assert_equal RecordingStudioAttachable::SafeRemoteFetch::OPEN_TIMEOUT, options[:open_timeout]

      http = Object.new
      http.define_singleton_method(:request) do |request|
        captured_body = URI.decode_www_form(request.body).to_h
        response
      end

      block.call(http)
    }) do
      Time.stub(:current, Time.at(1_700_000_000)) do
        result = client.exchange_code(code: "auth-code", code_verifier: "verifier-1")

        assert_equal "token-1", result.fetch("access_token")
        assert_equal 1_700_000_120, result.fetch("expires_at")
      end
    end

    assert_equal "auth-code", captured_body.fetch("code")
    assert_equal "verifier-1", captured_body.fetch("code_verifier")
    assert_equal "authorization_code", captured_body.fetch("grant_type")
  end

  def test_authorization_url_requires_configured_credentials
    unconfigured = RecordingStudioAttachable::Dropbox::Configuration.new
    oauth_client = RecordingStudioAttachable::Dropbox::OAuthClient.new(configuration: unconfigured)

    error = assert_raises(RecordingStudioAttachable::DependencyUnavailableError) do
      oauth_client.authorization_url(state: "missing", code_challenge: "challenge")
    end

    assert_equal "Dropbox addon is missing client credentials or redirect URI", error.message
  end

  private

  def client
    @client ||= RecordingStudioAttachable::Dropbox::OAuthClient.new(configuration: configured_dropbox)
  end

  def configured_dropbox
    @configured_dropbox ||= RecordingStudioAttachable::Dropbox::Configuration.new.tap do |configuration|
      configuration.merge!(
        client_id: "client-id",
        client_secret: "client-secret",
        redirect_uri: "https://example.test/oauth/callback"
      )
    end
  end
end
