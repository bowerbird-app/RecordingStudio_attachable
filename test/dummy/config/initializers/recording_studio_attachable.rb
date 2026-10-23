# frozen_string_literal: true

RecordingStudioAttachable.configure do |config|
  config.max_file_size = 25.megabytes
  config.image_processing_enabled = true
  config.image_processing_max_width = 1200
  config.image_processing_max_height = 1200
  config.image_processing_quality = 0.75
  # Dummy-only public host for direct URL demos. Studio UI stays on :rails.
  # :poster is a host-added custom variant. Leave preprocessed_variants unset so
  # the default (small/med/large + host-added names) picks it up automatically.
  config.url_mode = :rails
  config.direct_url_host = "images.example.test"
  config.image_variants = {
    poster: { resize_to_limit: [1280, 720] }
  }
  config.google_drive.enabled = true
  config.google_drive.api_key = ENV["DUMMY_GOOGLE_PICKER_API_KEY"].presence ||
                                ENV.fetch("DUMMY_GOOGLE_DRIVE_API_KEY", "dummy-google-drive-api-key")
  config.google_drive.app_id = ENV["DUMMY_GOOGLE_CLOUD_PROJECT_NUMBER"].presence ||
                               ENV.fetch("DUMMY_GOOGLE_DRIVE_APP_ID", "dummy-google-drive-app-id")

  config.dropbox.enabled = true
  config.dropbox.client_id = ENV.fetch("DUMMY_DROPBOX_CLIENT_ID", "dummy-dropbox-client-id")

  config.register_upload_provider(
    :demo_cloud,
    label: "Demo cloud import",
    icon: "cloud",
    url: ->(route_helpers:, recording:) do
      route_helpers.demo_upload_provider_path(recording_id: recording.id)
    end
  )
end
