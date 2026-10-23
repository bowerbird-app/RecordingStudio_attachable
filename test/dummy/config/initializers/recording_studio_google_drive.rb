# frozen_string_literal: true

require Rails.root.join("app/models/fake_oauth")

RecordingStudioGoogleDrive.configure do |config|
  client_id = Rails.application.credentials.dig(:attachable, :google_drive, :client_id).to_s.strip
  client_secret = Rails.application.credentials.dig(:attachable, :google_drive, :client_secret).to_s.strip
  use_real_google = client_id.present? && client_secret.present? && !Rails.env.test?

  if use_real_google
    config.authorize_url = "https://accounts.google.com/o/oauth2/v2/auth"
    config.token_url = "https://oauth2.googleapis.com/token"
    config.revoke_url = "https://oauth2.googleapis.com/revoke"
    config.client_id = client_id
    config.client_secret = client_secret
    config.extra_authorize_params = {
      "access_type" => "offline",
      "prompt" => "consent"
    }
  else
    config.authorize_url = "/fake_oauth/authorize"
    config.token_url = "/fake_oauth/token"
    config.revoke_url = "/fake_oauth/revoke"
    config.client_id = FakeOauth::CLIENT_ID
    config.client_secret = FakeOauth::CLIENT_SECRET
    config.http = FakeOauth
  end

  config.scopes = ["https://www.googleapis.com/auth/drive.readonly"]
end
