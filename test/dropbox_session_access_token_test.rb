# frozen_string_literal: true

require "test_helper"
require_relative "../lib/recording_studio_attachable/dropbox/session_access_token"

class DropboxSessionAccessTokenTest < Minitest::Test
  def setup
    @configuration = RecordingStudioAttachable::Dropbox::Configuration.new
    @configuration.merge!(
      enabled: true,
      client_id: "client-id",
      client_secret: "client-secret",
      redirect_uri: "https://example.test/callback"
    )
  end

  def test_fetch_returns_current_token_when_not_expired
    session = {
      "recording_studio_attachable_dropbox" => {
        "tokens" => { "access_token" => "token-1", "expires_at" => Time.current.to_i + 3600 }
      }
    }

    token = RecordingStudioAttachable::Dropbox::SessionAccessToken.fetch(
      session: session,
      configuration: @configuration
    )

    assert_equal "token-1", token
  end

  def test_fetch_refreshes_an_expiring_token
    session = {
      "recording_studio_attachable_dropbox" => {
        "tokens" => {
          "access_token" => "old-token",
          "refresh_token" => "refresh-1",
          "expires_at" => Time.current.to_i + 10
        }
      }
    }
    oauth_client = Object.new
    oauth_client.define_singleton_method(:refresh_token) do |refresh_token:|
      raise "wrong refresh token" unless refresh_token == "refresh-1"

      { "access_token" => "new-token", "refresh_token" => "refresh-2", "expires_at" => Time.current.to_i + 3600 }
    end

    token = RecordingStudioAttachable::Dropbox::SessionAccessToken.fetch(
      session: session,
      configuration: @configuration,
      oauth_client: oauth_client
    )

    assert_equal "new-token", token
    assert_equal "new-token", session.dig("recording_studio_attachable_dropbox", "tokens", "access_token")
    assert_equal "refresh-2", session.dig("recording_studio_attachable_dropbox", "tokens", "refresh_token")
  end

  def test_fetch_raises_when_disconnected
    error = assert_raises(RecordingStudioAttachable::Error) do
      RecordingStudioAttachable::Dropbox::SessionAccessToken.fetch(
        session: {},
        configuration: @configuration
      )
    end

    assert_equal "Connect Dropbox before importing files", error.message
  end

  def test_fetch_raises_when_refresh_token_is_missing
    session = {
      "recording_studio_attachable_dropbox" => {
        "tokens" => { "access_token" => "old-token", "expires_at" => Time.current.to_i }
      }
    }

    error = assert_raises(RecordingStudioAttachable::Error) do
      RecordingStudioAttachable::Dropbox::SessionAccessToken.fetch(
        session: session,
        configuration: @configuration
      )
    end

    assert_equal "Reconnect Dropbox to continue", error.message
  end
end
