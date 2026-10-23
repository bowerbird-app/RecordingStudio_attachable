# frozen_string_literal: true

require Rails.root.join("app/models/fake_oauth")

RecordingStudioGoogleDrive.configure do |config|
  rails_creds = begin
    Rails.application.credentials
  rescue ActiveSupport::EncryptedFile::MissingKeyError, Errno::ENOENT, ArgumentError
    nil
  end
  nested = rails_creds&.dig(:attachable, :google_drive).presence || rails_creds&.dig(:google_drive).presence || {}
  creds = {
    client_id: nested[:client_id].presence || ENV["GOOGLE_DRIVE_CLIENT_ID"].presence,
    client_secret: nested[:client_secret].presence || ENV["GOOGLE_DRIVE_CLIENT_SECRET"].presence,
    api_key: nested[:api_key].presence || ENV["GOOGLE_DRIVE_API_KEY"].presence,
    app_id: nested[:app_id].presence || ENV["GOOGLE_DRIVE_APP_ID"].presence
  }
  real_google = creds[:client_id].present? && creds[:client_secret].present? && !Rails.env.test?

  if real_google
    config.authorize_url = "https://accounts.google.com/o/oauth2/v2/auth"
    config.token_url = "https://oauth2.googleapis.com/token"
    config.revoke_url = "https://oauth2.googleapis.com/revoke"
    config.client_id = creds[:client_id]
    config.client_secret = creds[:client_secret]
    config.http = nil
  else
    config.authorize_url = "/fake_oauth/authorize"
    config.token_url = "/fake_oauth/token"
    config.revoke_url = "/fake_oauth/revoke"
    config.client_id = FakeOauth::CLIENT_ID
    config.client_secret = FakeOauth::CLIENT_SECRET
    config.http = FakeOauth
  end

  config.scopes = RecordingStudioGoogleDrive::AttachableConfiguration::DEFAULT_SCOPES

  config.attachable.enabled = true
  config.attachable.api_key = creds[:api_key].presence || "dummy-google-drive-picker-api-key"
  config.attachable.app_id = creds[:app_id].presence || "dummy-google-drive-picker-app-id"
end
