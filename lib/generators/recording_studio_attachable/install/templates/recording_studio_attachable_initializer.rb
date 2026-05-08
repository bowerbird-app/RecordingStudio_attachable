# frozen_string_literal: true

RecordingStudioAttachable.configure do |config|
  config.allowed_content_types = ["image/*", "application/pdf"]
  config.max_file_size = 25.megabytes
  # Maximum number of files accepted in a single upload or import request.
  config.max_file_count = 20
  config.enabled_attachment_kinds = %i[image file]
  config.default_listing_scope = :direct
  config.default_kind_filter = :all

  # Optional browser-side image preprocessing before direct upload. JPEG, PNG,
  # and WebP files are resized down to fit these bounds before uploading.
  # GIF, SVG, HEIC/HEIF, and unsupported image types upload unchanged.
  # config.image_processing_enabled = true
  # config.image_processing_max_width = 2560
  # config.image_processing_max_height = 2560
  # config.image_processing_quality = 0.82

  # Optional server-side image delivery variants. The original blob is kept as
  # uploaded, and generated variants are stored in the same Active Storage
  # service as the original (for example S3). Keep the public variant names
  # stable and override only the transformation sizes if your host app needs
  # different defaults.
  # config.image_variants = {
  #   square_small: { resize_to_fill: [128, 128] },
  #   square_med: { resize_to_fill: [400, 400] },
  #   square_large: { resize_to_fill: [800, 800] },
  #   small: { resize_to_limit: [480, 480] },
  #   med: { resize_to_limit: [960, 960] },
  #   large: { resize_to_limit: [1600, 1600] },
  #   xlarge: { resize_to_limit: [2400, 2400] }
  # }

  # Use the gem's blank layout by default, or set a host app layout like "application".
  config.layout = :blank
  config.auth_roles = {
    view: :view,
    upload: :edit,
    revise: :edit,
    remove: :admin,
    restore: :admin,
    download: :view
  }

  # Optional: addon gems can register extra upload sources on the upload page.
  # config.register_upload_provider(
  #   :google_drive,
  #   label: "Google Drive",
  #   icon: "cloud",
  #   strategy: :client_picker,
  #   launcher: "google_drive",
  #   bootstrap_url: ->(route_helpers:, recording:) { route_helpers.google_drive.recording_bootstrap_path(recording, format: :json) },
  #   import_url: ->(route_helpers:, recording:) { route_helpers.google_drive.recording_imports_path(recording, format: :json) }
  # )
  #
  # Built-in Google Drive addon:
  # config.google_drive.enabled = true
  # config.google_drive.client_id = ENV["GOOGLE_DRIVE_CLIENT_ID"]
  # config.google_drive.client_secret = ENV["GOOGLE_DRIVE_CLIENT_SECRET"]
  # config.google_drive.api_key = ENV["GOOGLE_DRIVE_API_KEY"]
  # config.google_drive.app_id = ENV["GOOGLE_DRIVE_APP_ID"]
  # config.google_drive.redirect_uri = "https://your-app.test/recording_studio_attachable/google_drive/oauth/callback"
  #
  # The engine mounts the Google Drive routes under:
  # /recording_studio_attachable/google_drive
  #
  # The Google Drive provider button is only registered when the addon is enabled
  # and the OAuth + Picker credentials above are present. The built-in button
  # opens Google auth and the Google Picker directly from the upload page.
  #
  # Then, inside your provider controller or service, call:
  # RecordingStudioAttachable::Services::ImportAttachment.call(
  #   parent_recording: recording,
  #   io: downloaded_file,
  #   filename: remote_file.name,
  #   content_type: remote_file.mime_type,
  #   # identify defaults to true; only disable it for trusted providers that
  #   # already know the file metadata is accurate.
  #   source: "google_drive",
  #   metadata: { provider: "google_drive", external_id: remote_file.id }
  # )
  #
  # Or register a browser launcher with
  # `registerUploadProviderLauncher("provider_name", launcher)` and have it
  # fetch `bootstrap_url`, open any auth popup it needs, then post selected
  # remote file ids back to `import_url`.
end
