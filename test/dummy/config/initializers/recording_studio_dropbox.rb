# frozen_string_literal: true

dropbox_app = begin
  creds = Rails.application.credentials
  nested = creds.dig(:attachable, :dropbox) || creds[:dropbox]
  nested.respond_to?(:to_h) ? nested.to_h.symbolize_keys : {}
rescue ActiveSupport::EncryptedFile::MissingKeyError, Errno::ENOENT, ArgumentError
  {}
end

client_id = dropbox_app[:client_id].presence ||
  ENV["DROPBOX_APP_KEY"].presence ||
  ENV["DROPBOX_CLIENT_ID"].presence
client_secret = dropbox_app[:client_secret].presence ||
  ENV["DROPBOX_APP_SECRET"].presence ||
  ENV["DROPBOX_CLIENT_SECRET"].presence
use_fake = Rails.env.test? || client_id.blank? || client_secret.blank?

RecordingStudioDropbox.configure do |config|
  config.enabled = true
  config.client_id = client_id.presence || "test-dropbox-app-key"
end

if use_fake
  require Rails.root.join("app/models/fake_dropbox_oauth")

  RecordingStudioDropbox.register_oauth_provider(
    authorize_url: "/fake_oauth/authorize",
    token_url: "/fake_oauth/token",
    revoke_url: "/fake_oauth/revoke",
    client_id: FakeDropboxOauth::CLIENT_ID,
    client_secret: FakeDropboxOauth::CLIENT_SECRET,
    http: FakeDropboxOauth
  )
else
  RecordingStudioDropbox.register_oauth_provider(
    client_id: client_id,
    client_secret: client_secret
  )
end
