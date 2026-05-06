# frozen_string_literal: true

RecordingStudioAttachable.configure do |config|
  config.google_drive.enabled = true
  config.google_drive.client_id = ENV.fetch("DUMMY_GOOGLE_DRIVE_CLIENT_ID", "dummy-google-drive-client-id")
  config.google_drive.client_secret = ENV.fetch("DUMMY_GOOGLE_DRIVE_CLIENT_SECRET", "dummy-google-drive-client-secret")
  config.google_drive.api_key = ENV.fetch("DUMMY_GOOGLE_DRIVE_API_KEY", "dummy-google-drive-api-key")
  config.google_drive.app_id = ENV.fetch("DUMMY_GOOGLE_DRIVE_APP_ID", "dummy-google-drive-app-id")
  config.google_drive.redirect_uri = ENV.fetch(
    "DUMMY_GOOGLE_DRIVE_REDIRECT_URI",
    "http://127.0.0.1:3000/recording_studio_attachable/google_drive/oauth/callback"
  )

  config.register_upload_provider(
    :demo_cloud,
    label: "Demo cloud import",
    icon: "cloud",
    url: ->(route_helpers:, recording:) do
      route_helpers.demo_upload_provider_path(recording_id: recording.id)
    end
  )
end