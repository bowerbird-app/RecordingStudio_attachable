# frozen_string_literal: true

require Rails.root.join("app/models/fake_oauth")

client_id = Rails.application.credentials.dig(:attachable, :dropbox, :client_id).to_s.strip
client_secret = Rails.application.credentials.dig(:attachable, :dropbox, :client_secret).to_s.strip
use_real_dropbox = client_id.present? && client_secret.present? && !Rails.env.test?

if use_real_dropbox
  RecordingStudioDropbox.register_oauth_provider(
    authorize_url: "https://www.dropbox.com/oauth2/authorize",
    token_url: "https://api.dropboxapi.com/oauth2/token",
    client_id: client_id,
    client_secret: client_secret,
    extra_authorize_params: { "token_access_type" => "offline" }
  )
else
  RecordingStudioDropbox.register_oauth_provider(
    authorize_url: "/fake_oauth/authorize",
    token_url: "/fake_oauth/token",
    revoke_url: "/fake_oauth/revoke",
    client_id: FakeOauth::CLIENT_ID,
    client_secret: FakeOauth::CLIENT_SECRET,
    http: FakeOauth
  )
end
