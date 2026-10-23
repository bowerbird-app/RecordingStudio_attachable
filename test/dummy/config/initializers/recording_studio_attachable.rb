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
  config.register_upload_provider(
    :demo_cloud,
    label: "Demo cloud import",
    icon: "cloud",
    url: ->(route_helpers:, recording:) do
      route_helpers.demo_upload_provider_path(recording_id: recording.id)
    end
  )
end
