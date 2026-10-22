# frozen_string_literal: true

RecordingStudioAttachable.configure do |config|
  config.allowed_content_types = ["image/*", "application/pdf"]
  config.max_file_size = 25.megabytes
  # Optional. Requires RecordingStudio_stripe in the host app.
  # config.storage_limit = :storage_bytes
  # Maximum number of files accepted in a single upload or import request.
  config.max_file_count = 20
  # Cap on unattached direct uploads waiting for this actor on one root.
  # config.pending_upload_limit = 20
  # Hosts that import by URL list the HTTPS hosts SafeRemoteFetch may contact.
  # config.import_allowed_hosts = ["cdn.example.com"]
  # Signed direct-upload URLs expire after this. Independent of Active Storage's
  # service URL expiry.
  # config.direct_upload_expires_in = 5.minutes
  # PurgeUnattachedBlobsJob deletes unattached blobs this gem created, older than
  # unattached_blob_ttl. It does nothing until purge_unattached_blobs is true.
  # config.unattached_blob_ttl = 24.hours
  # config.purge_unattached_blobs = true
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

  # Delivery URL mode. :rails (default) keeps authorized engine paths.
  # :direct builds public https://<direct_url_host>/<blob key> links for a
  # custom domain in front of the same object store (for example Cloudflare R2).
  # Separate from default_listing_scope: :direct (which means listing children).
  # config.url_mode = :rails
  # config.direct_url_host = "images.featuredin.press"
  #
  # After commit, preprocess small/med/large plus any host-added custom
  # image_variants names. Set preprocessed_variants to override exactly.
  # config.image_variants = { poster: { resize_to_limit: [1280, 720] } }
  # config.preprocessed_variants = %i[small med large poster]

  # Use the gem's blank layout by default, or set a host app layout like "application".
  config.layout = :blank

  # How Add buttons open the standard upload page: :page (navigate) or :modal
  # (a FlatPack modal on the current page). Buttons and editors can override it.
  config.upload_presentation = :page
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
  #   remote_importer: lambda do |parent_recording:, attachments:, actor: nil, impersonator: nil, context: nil|
  #     # `attachments` arrives as normalized remote selections from the shared
  #     # upload queue. Each entry includes `provider_payload`, optional name /
  #     # description overrides, and provider-stamped metadata.
  #     YourProvider::Services::ImportSelectedFiles.call(
  #       parent_recording: parent_recording,
  #       file_ids: attachments.map { |payload| payload.fetch(:provider_payload) },
  #       actor: actor,
  #       impersonator: impersonator
  #     )
  #   end
  # )
  #
  # Built-in cloud adapters are off until you enable them and supply credentials.
  # An adapter is registered and shown only when enabled AND fully configured.
  #
  # Google Drive (optional). Bundle recording_studio_google_drive >= 0.2.0, < 1.0
  # and recording_studio_oauth >= 0.14.1, < 1.0. Oauth stores tokens. This gem
  # only needs Picker keys:
  # config.google_drive.enabled = true
  # config.google_drive.api_key = ENV["GOOGLE_DRIVE_API_KEY"] # Browser API key for Google Picker
  # config.google_drive.app_id = ENV["GOOGLE_DRIVE_APP_ID"]   # Google Cloud project number
  #
  # Dropbox (OAuth redirect URI and scopes files.metadata.read + files.content.read):
  # config.dropbox.enabled = true
  # config.dropbox.client_id = ENV["DROPBOX_CLIENT_ID"]
  # config.dropbox.client_secret = ENV["DROPBOX_CLIENT_SECRET"]
  # config.dropbox.redirect_uri = "https://your-app.test/recording_studio_attachable/dropbox/oauth/callback"
  #
  # Adapter routes live under the engine mount, for example:
  # /recording_studio_attachable/google_drive
  # /recording_studio_attachable/dropbox
  #
  # Then, inside your provider controller or service, call:
  # RecordingStudioAttachable::Services::ImportAttachment.call(
  #   parent_recording: recording,
  #   io: downloaded_file,
  #   filename: remote_file.name,
  #   content_type: remote_file.mime_type,
  #   # The declared type is kept. The bytes are sniffed and a mismatch is rejected.
  #   source: "google_drive",
  #   metadata: { provider: "google_drive", external_id: remote_file.id }
  # )
  #
  # Or register a browser launcher with
  # `registerUploadProviderLauncher("provider_name", launcher)` and have it
  # fetch `bootstrap_url`, open any auth popup it needs, then add normalized
  # provider selections into the shared upload queue. The queue posts to
  # `recording_attachment_imports_path(recording)` and invokes your provider's
  # `remote_importer` hook during finalization.
end
