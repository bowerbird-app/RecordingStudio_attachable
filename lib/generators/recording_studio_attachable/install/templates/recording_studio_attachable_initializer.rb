# frozen_string_literal: true

RecordingStudioAttachable.configure do |config|
  config.allowed_content_types = ["image/*", "application/pdf"]
  config.max_file_size = 25.megabytes
  config.max_file_count = 20
  config.enabled_attachment_kinds = %i[image file]
  config.default_listing_scope = :direct
  config.default_kind_filter = :all
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
  #   source: "google_drive",
  #   metadata: { provider: "google_drive", external_id: remote_file.id }
  # )
  #
  # Or register a browser launcher with
  # `registerUploadProviderLauncher("provider_name", launcher)` and have it
  # fetch `bootstrap_url`, open any auth popup it needs, then post selected
  # remote file ids back to `import_url`.
end
