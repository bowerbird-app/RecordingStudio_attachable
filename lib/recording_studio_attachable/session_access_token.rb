# frozen_string_literal: true

module RecordingStudioAttachable
  class SessionAccessToken
    def self.fetch(session:, configuration: nil, oauth_client: nil)
      new(session:, configuration: configuration, oauth_client: oauth_client).fetch
    end

    def initialize(session:, configuration: nil, oauth_client: nil)
      @session = session
      @configuration = configuration || default_configuration
      @oauth_client = oauth_client
    end

    def fetch
      access_token = current_access_token
      return access_token unless refresh_needed?

      refreshed_access_token(current_refresh_token)
    end

    private

    attr_reader :session, :configuration

    def current_access_token
      tokens["access_token"].presence || raise(RecordingStudioAttachable::Error, connect_message)
    end

    def current_refresh_token
      tokens["refresh_token"].presence || raise(RecordingStudioAttachable::Error, reconnect_message)
    end

    def refreshed_access_token(refresh_token)
      merged = merged_tokens(oauth_client.refresh_token(refresh_token: refresh_token))
      storage["tokens"] = merged
      merged.fetch("access_token")
    end

    def merged_tokens(refreshed)
      tokens.merge(refreshed.slice("access_token", "refresh_token", "expires_at"))
    end

    def storage
      session[session_key] ||= {}
    end

    def tokens
      storage.fetch("tokens", {})
    end

    def refresh_needed?
      expires_at = tokens["expires_at"].to_i
      expires_at.positive? && expires_at <= Time.current.to_i + 30
    end

    def oauth_client
      @oauth_client ||= build_oauth_client
    end

    def connect_message
      "Connect #{provider_name} before importing files"
    end

    def reconnect_message
      "Reconnect #{provider_name} to continue"
    end
  end
end
