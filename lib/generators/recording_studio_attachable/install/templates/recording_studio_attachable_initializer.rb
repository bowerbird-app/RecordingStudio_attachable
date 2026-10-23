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

  # Optional: a provider gem registers itself. Hosts add the gem and, if the gem
  # does not auto-register, call register_upload_provider with the contract below.
  # config.register_upload_provider(
  #   :my_cloud,
  #   label: "My Cloud",
  #   icon: "cloud",
  #   strategy: :client_picker,
  #   launcher: "my_cloud",
  #   launcher_module: "my_cloud/picker_launcher",
  #   bootstrap_url: ->(route_helpers:, recording:) {
  #     route_helpers.my_cloud.recording_bootstrap_path(recording, format: :json)
  #   },
  #   import_url: ->(route_helpers:, recording:) {
  #     route_helpers.my_cloud.recording_imports_path(recording, format: :json)
  #   },
  #   allowed_payload_keys: %w[id],
  #   remote_importer: lambda do |parent_recording:, attachments:, actor: nil, impersonator: nil, **|
  #     RecordingStudioAttachable::Services::ImportRemoteFiles.call(
  #       parent_recording: parent_recording,
  #       provider_key: :my_cloud,
  #       actor: actor,
  #       impersonator: impersonator,
  #       payloads: attachments.map { |payload|
  #         {
  #           download: -> { { io: StringIO.new(""), filename: "file.bin", content_type: "application/octet-stream" } },
  #           filename: payload.dig(:provider_payload, "id"),
  #           metadata: { external_id: payload.dig(:provider_payload, "id") }
  #         }
  #       }
  #     )
  #   end,
  #   connect: ->(recording:, context:) {
  #     {
  #       url: "/my_cloud/connect",
  #       method: "post",
  #       fields: { authenticity_token: context.provider_csrf_token },
  #       fallback_url: "/my_cloud/connect"
  #     }
  #   },
  #   reconnect_error: ->(error) { error.is_a?(RecordingStudioAttachable::ReconnectRequired) }
  # )
  #
  # A provider gem mounts with:
  # ActiveSupport.on_load(:recording_studio_attachable) do
  #   RecordingStudioAttachable.register_adapter_routes(:my_cloud) do
  #     mount MyCloud::Engine, at: "/my_cloud", as: :my_cloud
  #   end
  # end
  #
  # Provider controllers inherit RecordingStudioAttachable::ProviderController
  # and set `self.upload_provider_key = :my_cloud`. Pin the gem's launcher, and
  # import helpers from "recording_studio_attachable/provider_launchers".
end
