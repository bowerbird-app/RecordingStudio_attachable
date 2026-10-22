# frozen_string_literal: true

require Rails.root.join("app/models/fake_oauth")

RecordingStudioGoogleDrive.configure do |config|
  config.authorize_url = "/fake_oauth/authorize"
  config.token_url = "/fake_oauth/token"
  config.revoke_url = "/fake_oauth/revoke"
  config.client_id = FakeOauth::CLIENT_ID
  config.client_secret = FakeOauth::CLIENT_SECRET
  config.http = FakeOauth
end
