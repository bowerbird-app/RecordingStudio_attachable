# frozen_string_literal: true

codespaces_redirect_uri = if ENV["CODESPACE_NAME"].present? && ENV["GITHUB_CODESPACES_PORT_FORWARDING_DOMAIN"].present?
  "https://#{ENV.fetch("CODESPACE_NAME")}-3000.#{ENV.fetch("GITHUB_CODESPACES_PORT_FORWARDING_DOMAIN")}/recording_studio_attachable/google_drive/oauth/callback"
else
  "http://127.0.0.1:3000/recording_studio_attachable/google_drive/oauth/callback"
end

RecordingStudioAttachable.configure do |config|
  config.max_file_size = 25.megabytes
  config.image_processing_enabled = true
  config.image_processing_max_width = 1200
  config.image_processing_max_height = 1200
  config.image_processing_quality = 0.75
  config.google_drive.enabled = true
  config.google_drive.client_id = ENV["DUMMY_GOOGLE_OAUTH_CLIENT_ID"].presence ||
                                  ENV.fetch("DUMMY_GOOGLE_DRIVE_CLIENT_ID", "dummy-google-drive-client-id")
  config.google_drive.client_secret = ENV["DUMMY_GOOGLE_CLIENT_SECRET"].presence ||
                                      ENV.fetch("DUMMY_GOOGLE_DRIVE_CLIENT_SECRET", "dummy-google-drive-client-secret")
  config.google_drive.api_key = ENV["DUMMY_GOOGLE_PICKER_API_KEY"].presence ||
                                ENV.fetch("DUMMY_GOOGLE_DRIVE_API_KEY", "dummy-google-drive-api-key")
  config.google_drive.app_id = ENV["DUMMY_GOOGLE_CLOUD_PROJECT_NUMBER"].presence ||
                               ENV.fetch("DUMMY_GOOGLE_DRIVE_APP_ID", "dummy-google-drive-app-id")
  config.google_drive.redirect_uri = ENV["DUMMY_GOOGLE_REDIRECT_URI"].presence ||
                                     ENV.fetch("DUMMY_GOOGLE_DRIVE_REDIRECT_URI", codespaces_redirect_uri)

  config.register_upload_provider(
    :demo_cloud,
    label: "Demo cloud import",
    icon: "cloud",
    url: ->(route_helpers:, recording:) do
      route_helpers.demo_upload_provider_path(recording_id: recording.id)
    end
  )
end
