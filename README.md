# Recording Studio Attachable

Optional Recording Studio addon gem for uploading and managing images/files as child recordings beneath a recording.

## Highlights

- `include RecordingStudio::Capabilities::Attachable.to(...)` opt-in API for parent recordables
- addon-owned `RecordingStudioAttachable::Attachment` recordable with `has_one_attached :file`
- child recording identity with append-only recordable revisions
- FlatPack-based grid/list library, search, bulk remove, upload, and picker UI slice
- Stimulus + Active Storage direct upload flow
- Accessible-backed authorization and Trashable-aware removal when available

## Requirements

- Ruby 3.3+
- Rails 8.1+
- Active Storage installed in the host app
- Recording Studio 4.2.0 or newer installed in the host app
- RecordingStudio Accessible installed for the default authorization adapter
- RecordingStudio Trashable installed if you want restore support for removed attachments
- RecordingStudio Metrics `>= 0.3.0, < 1.0` (latest GitHub tag `v0.5.0`) for operations-API storage and upload metrics
- Optional Google Drive import: `recording_studio_google_drive` `>= 0.2.0, < 1.0` and `recording_studio_oauth` `>= 0.14.1, < 1.0`. Attachable does not depend on those gems at runtime.

## Quick start

1. Add the gem to your host app.
2. Ensure Active Storage and RecordingStudio Accessible are installed.
3. Run `rails generate recording_studio_attachable:install`.
4. Run `rails generate recording_studio_attachable:migrations`. Each copied file is stamped one second after the previous file.
5. Run `rails db:migrate`.
6. Declare each host-app domain recordable with `recording_studio_recordable(...)`.
7. Opt parent recordables into `include RecordingStudio::Capabilities::Attachable.to(...)`. Installing the gem does not enable `:attachable`.

## Host app setup

### 1. Add the gem

```ruby
# Gemfile
gem "recording_studio_attachable"
```

### 2. Declare host-app recordable hierarchy

```ruby
class Workspace < ApplicationRecord
  recording_studio_recordable label: "Workspace", root: true
end

class Page < ApplicationRecord
  recording_studio_recordable(
    label: "Page",
    root: false,
    allowed_parent_types: ["Workspace"]
  )
end
```

Recording Studio 4 requires every configured host-app recordable to declare whether it can be a root and, for non-root domain recordables, which parent types are allowed.

Do not enable `:attachable` on a shared root (`shared: true`). Attachments are capability-owned children, so enable the capability on domain recordables beneath that shared root instead.

`RecordingStudioAttachable::Attachment` is owned by this addon. The addon declares it as `root: false` and registers it as a child recordable of the `:attachable` capability, so host apps should not add host-specific `allowed_parent_types:` to the attachment model.

### 3. Opt parent recordables into attachable

Installing this gem does not enable `:attachable`. Include `.to` on each parent recordable that should accept attachments. Parent rules stay on `recording_studio_recordable`.

```ruby
class Workspace < ApplicationRecord
  recording_studio_recordable label: "Workspace", root: true

  include RecordingStudio::Capabilities::Attachable.to(
    allowed_content_types: ["image/*", "application/pdf", "text/plain"],
    max_file_size: 25.megabytes,
    max_file_count: 20,
    enabled_attachment_kinds: %i[image file]
  )
end

class Page < ApplicationRecord
  recording_studio_recordable(
    label: "Page",
    root: false,
    allowed_parent_types: ["Workspace"]
  )

  include RecordingStudio::Capabilities::Attachable.to(
    allowed_content_types: ["image/*"],
    max_file_size: 25.megabytes,
    enabled_attachment_kinds: %i[image]
  )
end
```

### 4. Mount the engine

The install generator adds the mount for you. The default mount path is:

```ruby
mount RecordingStudioAttachable::Engine, at: "/recording_studio_attachable"
```

### 5. Wire direct uploads

Browser uploads POST to this engine's recording direct-upload route (`recordings/:id/attachments/direct_uploads`), not `/rails/active_storage/direct_uploads`. That route checks the upload role, content type, size, pending-upload cap, and storage capacity, then returns a signed id bound to that recording and actor.

The install generator also wires the Active Storage importmap pin, starts Active Storage in `app/javascript/application.js`, and eager-loads the engine Stimulus controllers from `app/javascript/controllers/index.js`.

If your app customizes those entrypoints, make sure all three of these remain true:

- `@rails/activestorage` is pinned in `config/importmap.rb`
- `ActiveStorage.start()` is called in `app/javascript/application.js`
- `controllers/recording_studio_attachable` is eager-loaded from the Stimulus controller index

## Configuration

The generator creates `config/initializers/recording_studio_attachable.rb` with these defaults:

```ruby
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

  # Optional server-side image delivery variants. The gem keeps the original
  # upload and generates delivery variants on demand, storing them in the same
  # Active Storage service as the source blob.
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
  # This is separate from default_listing_scope: :direct (listing children).
  # config.url_mode = :rails
  # config.direct_url_host = "images.featuredin.press"
  #
  # After commit, preprocess small/med/large plus any host-added custom
  # image_variants names (for example :poster). Set preprocessed_variants to
  # override that list exactly.
  # config.image_variants = { poster: { resize_to_limit: [1280, 720] } }
  # config.preprocessed_variants = %i[small med large poster]

  config.layout = :blank
  config.auth_roles = {
    view: :view,
    upload: :edit,
    revise: :edit,
    remove: :admin,
    restore: :admin,
    download: :view
  }
end
```

`max_file_size` is the largest single file. `storage_limit` is optional. It names a quantity limit for the total retained bytes on one root recording. Leave it unset, or set it to a blank value, and uploads do not ask Stripe for capacity.

```ruby
config.storage_limit = :storage_bytes
```

Configure the limit on the host's Stripe initializer. This gem does not depend on `recording_studio_stripe`.

```ruby
RecordingStudioStripe.configure do |config|
  config.subscription_types = { "studio" => { "label" => "Studio" } }
  config.limits = {
    "storage_bytes" => {
      "label" => "Storage",
      "aggregation" => "quantity",
      "subscription_type" => "studio"
    }
  }
end
```

The product stores the cap in Stripe metadata as `limit_<name>`. For the example above that key is `limit_storage_bytes`. Attachable registers the usage provider. The provider calls `RecordingStudioAttachable.storage_bytes_for(root)` and returns that integer. The total does not reset each billing period.

`storage_bytes_for` sums distinct original file blobs on attachment rows stamped with that root. The same blob counts once under one root. It counts again, in full, under every other root that still has it. Variant files are not included. Rows whose recording and events were already gone before the backfill stay uncounted. The total is an ActiveRecord query on the host connection.

### Operations API metrics

The gem registers site-wide `:attachments` metrics with RecordingStudio Metrics (`expose: { api: [:operations] }`). Values come from live `RecordingStudio::Recording` rows (`recordable_type` Attachment, `trashed_at: nil`) joined to the current recordable snapshot, not the raw attachment table.

| Identifier | MCP tool | Meaning |
| --- | --- | --- |
| `attachments.storage_used` | `attachments-storage_used` | Sum of `byte_size` on live current snapshots |
| `attachments.uploads_over_time` | `attachments-uploads_over_time` | Uploads over time |
| `attachments.by_kind` | `attachments-by_kind` | Breakdown by `attachment_kind` |
| `attachments.by_content_type` | `attachments-by_content_type` | Breakdown by `content_type` |

`attachments.uploads_over_time` takes `from`, `to`, and `interval` (`day`, `week`, `month`, `year`). The scalar and breakdown metrics do not take a window.

`api_authorize` is `RecordingStudioAttachable::Api::Access.can_view?`: AdminRoot `:view` through Recording Studio Accessible. The host calls `RecordingStudioMetrics::Api.register!(api: :operations)`. This gem does not register those metric endpoints. RecordingStudio MCP `0.17.0` builds one read-only tool per exposed metric from that registry.

### Attachment API

The upload, attach, and import actions are capability actions on the parent recording. They are registered when `RecordingStudioApi` is loaded. A host turns them on per recordable type.

1. Add `recording_studio_api` to the host app. Include `RecordingStudioApi::ApiClient` in Accessible `access_actor_types` so a provisioned client can hold the upload role.
2. Call `RecordingStudioAttachable::Api.register!`. The default API is `:public`. Pass the named admin APIs you also want:

```ruby
RecordingStudioAttachable::Api.register!(apis: [:public, :operations])
```

Configure a named API before you pass it. `register!` reads `config.auth_role_for(:upload)` at that moment. `import_attachment` uses `config.auth_roles[:import]` when that key exists, and `:upload` otherwise.

3. Allow the actions on each parent type. Registration alone does not expose them.

```ruby
RecordingStudioApi.register_recordable_type_api(
  "Workspace",
  operations: %i[index show],
  capability_actions: %i[create_upload attach import_attachment]
)
```

A press kit gem does the same on its image and file sections:

```ruby
RecordingStudioApi.register_recordable_type_api(
  "RecordingStudioPresskits::Images",
  operations: %i[index show],
  capability_actions: %i[update_image reorder_images remove_image create_upload attach import_attachment]
)

RecordingStudioApi.register_recordable_type_api(
  "RecordingStudioPresskits::Files",
  operations: %i[index show],
  capability_actions: %i[update_file reorder_files remove_file create_upload attach import_attachment]
)
```

A type that leaves those names off `capability_actions` does not show the actions in OpenAPI. Calling one returns the Recording Studio API's unsupported-action response.

`create_upload` takes `filename`, `byte_size`, `checksum`, and `content_type`. The checksum is the base64 MD5 of the bytes. The response is `signed_blob_id`, `upload` (`url` and `headers`), and `expires_at`. PUT the bytes to `upload.url` with `upload.headers`. The signed id uses the `:attachable_upload` purpose and expires after `config.direct_upload_expires_in` (default 5 minutes). It is bound to the parent recording and the actor that asked for it. `attach` accepts it once, and only while the blob is still unattached. The file bytes are sniffed and must match the declared content type.

`config.pending_upload_limit` (default 20) caps unattached uploads this gem issued for that actor on that root. `image/*` does not allow `image/svg+xml`. Name `image/svg+xml` in the allow list when a host wants SVG. File responses stream the bytes. PNG, JPEG, GIF, WebP, and PDF can be inline. Anything else is downloaded. Responses send `Content-Security-Policy: sandbox` and `X-Content-Type-Options: nosniff`.

Request logs filter `signed_blob_id` and `checksum`. This gem does not write the upload URL into a log line. The Recording Studio API request log stores allowlisted request params, not the response body.

The disk service builds that URL from the current request host. This gem includes `ActiveStorage::SetCurrent` on `RecordingStudioApi::ApiController` so the host is set. An S3 service returns a presigned URL and does not use the app host.

`attach` takes one file (`signed_blob_id`, and optional `name`, `description`, `caption`, `credit`, `alt_text`) or `attachments` as a list of those objects. The response is the new child attachment (`id`, `kind`, `name`, `urls`) or `{ attachments: [...] }` for a list.

`import_attachment` takes `url`, and optional `name` and `description`. Set `config.import_allowed_hosts` to the HTTPS hosts the host app trusts. Private addresses, non-HTTPS URLs, and any other host are rejected. The fetch uses `SafeRemoteFetch`.

Validation failures are `422` `invalid_input`. A caller without the upload role is `403`.

Browser clients that PUT straight to S3 need a CORS rule on the bucket. Allow `PUT` from the app origin, and allow the headers `Content-Type`, `Content-MD5`, and `Content-Disposition`. A server or other non-browser client sends those headers itself and does not need the CORS rule.

`create_upload` leaves an Active Storage blob before the client finishes the PUT. `PurgeUnattachedBlobsJob` deletes unattached blobs this gem tagged, older than `config.unattached_blob_ttl` (default 24 hours). It does nothing until `config.purge_unattached_blobs` is true. Other gems' unattached blobs stay. Schedule the job at least that often. With Solid Queue:

```yaml
# config/recurring.yml
purge_unattached_attachment_blobs:
  class: RecordingStudioAttachable::PurgeUnattachedBlobsJob
  schedule: every day at 3am
```

Or enqueue it from the host's own scheduler:

```ruby
RecordingStudioAttachable::PurgeUnattachedBlobsJob.perform_later
```

Trash and restore leave the file attached, so the total stays the same. Permanent deletion is `Recording#destroy!`. `RemoveAttachment` uses that when the recording has no Trashable hook. Trashable purge uses that after the recording is already trashed. Destroy detaches the file rows for the current attachment and earlier snapshots on that recording, then purges a blob that no other attachment still references. The total drops when those file rows are gone.

When browser-side image preprocessing is enabled, the gem's built-in direct-upload surfaces resize oversized JPEG, PNG, and WebP files before `DirectUpload` sends them to Active Storage. That includes the main upload page, the bundled attachment-image picker, and attachment file replacements on the revision screen. This is a best-effort optimization layer, not a security boundary: server-side content-type and byte-size validation still runs on the final uploaded blob. GIF, SVG, HEIC/HEIF, and other unsupported image types are uploaded unchanged.

For delivery, the engine uses a stable set of named image variants: `square_small`, `square_med`, `square_large`, `small`, `med`, `large`, and `xlarge`. Host apps can override the transformation sizes through `config.image_variants` while keeping those public names stable across engine views and integrations.

After an image attachment is committed, `PreprocessVariantsJob` processes `config.preprocessed_variants` so those sizes exist before a browser asks for them. The default is `small`, `med`, and `large`, plus every host-added custom name in `config.image_variants` (for example `:poster`). Other gem defaults such as `square_med` or `xlarge` are not auto-included. Assigning `preprocessed_variants` replaces that default with an exact list. The job is idempotent and skips non-image or unvariable files.

### URL modes

`config.url_mode` chooses how delivery URLs are built:

| Mode | Behaviour |
| --- | --- |
| `:rails` (default) | Authorized engine paths (`attachments/:id/file`, `attachments/:id/preview/:variant_name`). Unchanged from earlier releases. |
| `:direct` | Public `https://<direct_url_host>/<blob key>` links. No expiry, no presigning. Requires `config.direct_url_host`. |

Per-call override on the attachment:

```ruby
attachment.original_url(mode: :direct, rails_url: file_path)
attachment.url_for_variant(:med, mode: :direct, rails_url: preview_path)
```

`rails_url:` is required in `:rails` mode. In `:direct` mode it is the fallback when a named variant is not processed yet: the gem returns that authorized Rails preview path and enqueues preprocessing, rather than pointing at the original's direct URL (which would be the wrong size). For a processed resize, direct mode always uses the variant_record's image blob key, never the original blob key. Studio UI helpers keep Rails paths unless the host sets `config.url_mode = :direct`.

### Attachment image picker

The gem ships with a reusable image picker for browser-driven surfaces such as inline editors, chat composers, and custom attachment chips. The picker endpoint is `recording_attachment_picker_path(recording)` and always returns image attachments plus pagination metadata for the chosen parent recording.

In the browser, the bundled `recording-studio-attachable--attachment-image-picker` Stimulus controller loads that JSON into a FlatPack modal, supports search and direct uploads, and dispatches a `selected` event each time the user chooses an attachment. Consumers receive the selected attachment in `event.detail.attachment`.

```erb
<div
  data-controller="chat-demo recording-studio-attachable--attachment-image-picker"
  data-action="recording-studio-attachable--attachment-image-picker:selected->chat-demo#attachmentSelected"
  data-recording-studio-attachable--attachment-image-picker-picker-url-value="<%= recording_studio_attachable.recording_attachment_picker_path(@recording) %>"
  data-recording-studio-attachable--attachment-image-picker-upload-url-value="<%= recording_studio_attachable.recording_attachments_path(@recording) %>"
  data-recording-studio-attachable--attachment-image-picker-direct-upload-url-value="<%= recording_studio_attachable.recording_direct_uploads_path(@recording) %>">
</div>
```

```js
async attachmentSelected(event) {
  const { attachment } = event.detail || {}
  if (!attachment) return

  await this.persistAttachment(attachment.id)
  this.renderAttachmentChip({
    id: attachment.id,
    name: attachment.name,
    thumbnailUrl: attachment.thumbnail_url,
    fileUrl: attachment.insert_url,
    showPath: attachment.show_path
  })
}
```

The selection payload includes `id`, `name`, `thumbnail_url`, `insert_url`, `variant_urls`, `alt`, and `show_path`. If you are integrating with the FlatPack rich-text editor, the same controller can also listen for the toolbar event and insert the chosen image directly into Tiptap. For non-editor flows, prefer the event-driven integration so your app stays responsible for what happens after selection.

### Upload provider addons

Addon gems can register extra upload sources for the upload page without replacing the core direct-upload flow. The button registration API is the discovery layer, and providers can now choose one of three launch strategies:

- `:link` for normal navigation
- `:modal_page` for a provider-owned page rendered inside the shared upload-page modal
- `:client_picker` for browser-native or SDK-driven pickers launched directly from the upload page

The public import services remain the provider integration layer.

```ruby
RecordingStudioAttachable.configure do |config|
  config.register_upload_provider(
    :google_drive,
    label: "Google Drive",
    icon: "cloud",
    strategy: :client_picker,
    launcher: "google_drive",
    bootstrap_url: ->(route_helpers:, recording:) do
      route_helpers.google_drive.recording_bootstrap_path(recording, format: :json)
    end,
    remote_importer: lambda do |parent_recording:, attachments:, actor: nil, impersonator: nil, context: nil|
      MyAddon::Drive::ImportSelectedFiles.call(
        parent_recording: parent_recording,
        file_ids: attachments.map { |payload| payload.fetch(:provider_payload) },
        actor: actor,
        impersonator: impersonator
      )
    end
  )
end
```

Each provider registration supports:

- `key`: stable provider identifier
- `label`: button text shown on the upload page
- `strategy`: `:link`, `:modal_page`, or `:client_picker`
- `url`: string or callable for `:link`
- `bootstrap_url`: JSON bootstrap endpoint for `:client_picker`
- `launcher`: browser launcher name for `:client_picker`
- `remote_importer`: callable hook that materializes queued remote selections into attachments through the shared Attachable result contract
- `modal_title`: optional modal heading for `:modal_page`
- `icon`, `style`, `size`, `target`: FlatPack button options
- `visible`: optional callable receiving `view_context:` and `recording:`

The `remote_importer` hook is the public cloud-provider API. It receives:

- `parent_recording`
- `attachments`: normalized remote selections from the shared upload queue
- `actor`
- `impersonator`
- `context`: the request/controller context for session-backed provider auth

It must return the same `RecordingStudioAttachable::Services::BaseService::Result` shape used by the gem's other service APIs.

For `:modal_page`, the upload page opens the provider URL inside a shared FlatPack modal. The engine appends `embed=modal`, `provider_key`, and `provider_modal_id` to the provider URL so addon-owned screens can adapt their layout and communicate back to the upload page.

For modal-page providers, the shared browser contract is:

- the upload page opens the provider URL in an iframe modal
- addon screens can complete auth in a popup and post a `provider-auth-complete` message back to the upload page
- addon screens can post a `provider-import-complete` message with a `redirectPath` when the import succeeds

For `:client_picker`, the upload page stays in place and calls a registered browser launcher. Prefetch loads picker config only and does not write OAuth state, so Dropbox and Drive can warm up together without clobbering a cookie session. A click opens connect or the vendor picker. Google Drive connect uses Recording Studio Oauth outbound connections. Dropbox still creates OAuth state in the session. After OAuth completes, the cached bootstrap is dropped and fetched again. Drive then opens the Picker on its own. Dropbox waits for the next click on the same Dropbox button so `choose()` stays inside a user gesture. Chooser selections send the file id and filename; the shared imports endpoint copies the file through Dropbox’s API using the session token. Neither flow adds a second Choose from… button. Drive also refetches when the picker `access_token` is within 30 seconds of expiry. A `403` or `422` bootstrap disables the provider button after a click; prefetch failures stay quiet.

Client-picker launchers are registered in JavaScript:

```js
import { registerUploadProviderLauncher } from "controllers/recording_studio_attachable/provider_launchers"

registerUploadProviderLauncher("google_drive", {
  forget(bootstrapUrl) {
    // drop the cached bootstrap so relaunch after OAuth sees a connected session
  },
  prefetch({ controller, bootstrapUrl }) {
    return controller.fetchProviderBootstrap(bootstrapUrl)
  },
  async launch({ controller, providerKey, bootstrapUrl, gesture }) {
    const bootstrap = await controller.fetchProviderBootstrap(bootstrapUrl)
    // open auth popup or vendor picker inside the click when gesture is true
    controller.addProviderSelections(providerKey, [{ id: "file-1", resource_key: "rk-1" }])
  }
})
```

The upload page then posts the whole batch to `recording_attachment_imports_path(recording)`. Recording Studio Attachable owns the queue UI, retries, response handling, and redirect behavior; the provider only implements `remote_importer`.

In your provider controller or service, hand the gem an IO object plus the declared content type. The declared type is stored, the bytes are sniffed, and a mismatch is rejected. The gem then enforces attachable validations and creates the child recording:

```ruby
result = RecordingStudioAttachable::Services::ImportAttachment.call(
  parent_recording: recording,
  io: downloaded_file,
  filename: remote_file.name,
  content_type: remote_file.mime_type,
  actor: Current.actor,
  impersonator: Current.impersonator,
  name: remote_file.title,
  description: "Imported from Google Drive",
  source: "google_drive",
  metadata: {
    provider: "google_drive",
    external_id: remote_file.id,
    external_url: remote_file.web_view_link
  }
)

if result.success?
  attachment_recording = result.value
else
  Rails.logger.warn(result.error)
end
```

If your provider flow is browser-driven and you want an HTTP handoff endpoint instead of calling the service directly, the engine now exposes `recording_attachment_imports_path(recording)`. Post either uploaded files or signed blob ids to that endpoint and the engine will route the batch through the correct import/finalize service for you. This endpoint uses the host app's current actor and stamps provider provenance from the registered `provider_key`.

Multipart file imports:

```ruby
post recording_studio_attachable.recording_attachment_imports_path(recording), params: {
  attachment_import: {
    provider_key: "google_drive",
    attachments: [
      {
        file: downloaded_file,
        name: remote_file.title,
        description: "Imported from Google Drive"
      }
    ]
  }
}
```

Signed blob finalization with provider metadata. The blob comes from this gem's direct-upload route:

```ruby
post recording_studio_attachable.recording_attachment_imports_path(recording), params: {
  attachment_import: {
    provider_key: "google_drive",
    attachments: [
      {
        signed_blob_id: RecordingStudioAttachable::DirectUpload.sign(blob),
        name: remote_file.title,
        metadata: {
          external_id: remote_file.id,
          external_url: remote_file.web_view_link
        }
      }
    ]
  }
}, as: :json
```

For batched provider imports, use `RecordingStudioAttachable::Services::ImportAttachments.call(...)` with an `attachments:` array of hashes using the same keys.

If you are working in trusted internal app code and only want the created recording, the attachable recording also exposes convenience methods:

- `recording.import_attachment(...)`
- `recording.import_attachments(...)`

### Cloud upload adapters

Google Drive and Dropbox ship as optional adapters. Dropbox still owns its OAuth and session tokens. Google Drive import uses the `recording_studio_google_drive` gem for Drive API calls and Recording Studio Oauth outbound connections for tokens. Core owns the upload-provider registry, the generic `attachments/imports` endpoint, and a shared HTTPS fetch used by adapters that still download over HTTP.

Adapters are **off** until the host turns them on **and** supplies real credentials. Dummy placeholder values do not count. Hosts can enable Drive only, Dropbox only, both, or neither. When an adapter is off or incomplete, it is not registered, nothing from it appears on the upload page, and its endpoints refuse the request.

Files are always **copied** into Active Storage. There are no linked attachments.

#### Google Drive

Google Drive stays optional. This gem has no runtime dependency on `recording_studio_google_drive` or `recording_studio_oauth`. The Drive engine mounts and the upload-page button registers only when the host bundles the Google Drive gem.

1. Add `recording_studio_google_drive` `>= 0.2.0, < 1.0` and `recording_studio_oauth` `>= 0.14.1, < 1.0`.
2. Install and migrate Oauth (`recording_studio_oauth:install` and `recording_studio_oauth:migrations`).
3. Mount Oauth and set Google app credentials on the Oauth outbound provider (`recording_studio_oauth.outbound.google_drive`). Name the keys. Do not put the values in git.
4. Enable the Attachable picker keys:

```ruby
RecordingStudioAttachable.configure do |config|
  config.google_drive.enabled = true
  config.google_drive.api_key = ENV.fetch("GOOGLE_DRIVE_API_KEY")
  config.google_drive.app_id = ENV.fetch("GOOGLE_DRIVE_APP_ID")
end
```

`GOOGLE_DRIVE_API_KEY` must be a browser API key for the same Google Cloud project, and `GOOGLE_DRIVE_APP_ID` is the Google Cloud project number used by Google Picker.

Connect and reconnect use Oauth's outbound flow. Tokens are not stored in the Rails session. Without a connection, or when the Google Drive gem raises `ReconnectRequired`, the import UI shows Connect or Reconnect instead of a 500. Once connected, the upload page still launches Google Picker, then copies selected files through `ImportAttachments`. Bootstrap JSON may include a short-lived picker `access_token` and `expires_at`; that token is read from Oauth, not written to the session. Native Docs/Sheets/Slides export to PDF, PNG, or CSV as before. Routes live at `/recording_studio_attachable/google_drive`.

#### Dropbox

Create a Dropbox app with scoped access:

- Redirect URI: `https://your-app.test/recording_studio_attachable/dropbox/oauth/callback`
- Scopes: `files.metadata.read`, `files.content.read`

```ruby
RecordingStudioAttachable.configure do |config|
  config.dropbox.enabled = true
  config.dropbox.client_id = ENV.fetch("DROPBOX_CLIENT_ID")
  config.dropbox.client_secret = ENV.fetch("DROPBOX_CLIENT_SECRET")
  config.dropbox.redirect_uri = "https://your-app.test/recording_studio_attachable/dropbox/oauth/callback"
end
```

People sign in to their own Dropbox via OAuth 2.0 with PKCE. The Chooser returns file ids only. The server loads metadata and content through the Dropbox API with the user token. Client-supplied download URLs are ignored.

In the Dropbox app console, add this host to **Chooser / Saver domains** (for example `your-app.test`) so the Chooser can open.

Hosts with a Content Security Policy must allow the Chooser script at `https://www.dropbox.com/static/api/2/dropins.js` (`script-src`). Inline launcher imports use a CSP nonce via `javascript_tag`.

Dropbox OAuth tokens stay in the Rails session. Google Drive tokens do not. Hosts that enable Dropbox (or Dropbox plus Drive) should use a server-side session store (Redis, cache, or Active Record) so the browser’s 4 KB cookie limit is not hit.

#### Adding another provider

1. Add a self-contained adapter directory (engine, routes, config object, OAuth, resolve, launcher JS).
2. Register the config with `RecordingStudioAttachable.register_adapter_configuration(:your_key, Your::Configuration)`.
3. Mount routes with `RecordingStudioAttachable.register_adapter_routes { mount Your::Engine, at: "/your_key", as: :your_key }`.
4. When `enabled?` and `configured?`, `register_upload_provider` on the existing registry (`strategy: :client_picker`, `remote_importer`, `allowed_payload_keys`).
5. Resolve a selection to a `RecordingStudioAttachable::RemoteFile` (HTTPS URI, allowed hosts, headers, filename, content type, size, external id). Fetch with `RecordingStudioAttachable::SafeRemoteFetch`, then `ImportAttachments`.
6. Register a launcher with `registerUploadProviderLauncher("your_key", …)` in `your_key_picker_launcher.js`. The upload page imports that module only when the provider is shown.

Do not add a second registry. Do not special-case the new provider in core config, routes, or JS.

Each import payload supports:

- `io`: readable IO object for the provider file
- `filename`: original filename to store in Active Storage
- `content_type`: declared MIME type. It is stored as given and must match the type sniffed from the bytes
- `name`, `description`: optional attachment metadata overrides
- `actor`, `impersonator`: optional audit actors
- `source`: metadata source label stored on the recording event, defaults to `provider_import`; use this only in trusted direct service calls
- `metadata`: extra event metadata merged into the attachment upload event

The HTTP endpoint accepts a single `attachment_import` envelope plus either:

- `file`: a multipart uploaded file that the engine should import into Active Storage
- `signed_blob_id`: a signed id from this gem's direct-upload route (`purpose: :attachable_upload`), bound to this recording and actor

The HTTP endpoint does not accept caller-controlled `source` or `service_name` values. Provider provenance is derived from the registered `provider_key`.

### Per-recordable overrides

Capability options passed to `RecordingStudio::Capabilities::Attachable.to(...)` override the global defaults for that recordable type.

The most important per-recordable options are:

- `allowed_content_types`
- `max_file_size`
- `max_file_count` for a single upload or import batch, not the total lifetime attachment count on a recording
- `enabled_attachment_kinds`
- `auth_roles`
- `authorize_with`

## Helpers and queries

The engine exposes a small set of route helpers that host apps typically use directly:

- `recording_attachments_path(recording, scope: :direct, kind: :all)` for the library page
- `recording_attachment_upload_path(recording)` for the dedicated upload screen
- `recording_attachment_picker_path(recording)` for the image-picker JSON endpoint
- `recording_attachment_imports_path(recording)` for browser-driven multipart or signed-blob import handoff
- `attachment_path(attachment_recording)` for the attachment detail page
- `download_attachment_path(attachment_recording)` for authorized file downloads

For parent-recording lookups outside the UI, use `RecordingStudioAttachable::Queries::WithAttachments` to filter a `RecordingStudio::Recording` scope down to records that currently have attachments:

```ruby
recordings_with_images = RecordingStudioAttachable::Queries::WithAttachments.new(
  scope: RecordingStudio::Recording.all,
  recordable_type: "Page",
  kind: :images
).call

Page.where(id: recordings_with_images.select(:recordable_id))
```

The query accepts `scope:`, `kind:`, `recordable_type:`, and `include_trashed:`. `kind:` accepts `:image`, `:images`, `:file`, `:files`, or `:all`.

## Delivery

Attachment previews, editor insert URLs, and downloads default to engine-owned endpoints so each request stays behind the gem's authorization checks. With `config.url_mode = :rails` (the default), host apps should link to the engine paths returned by the gem instead of generating raw Active Storage blob URLs.

With `config.url_mode = :direct` and `config.direct_url_host` set, helpers and `Attachment#original_url` / `#url_for_variant` return public custom-domain URLs for blob keys. Downloads and other engine actions that stream bytes still use the authorized Rails endpoints.

### Layouts

Gem views use the bundled blank layout by default:

- centered container
- no top nav
- no sidebar

If you want the gem views to render inside your host app shell instead, set `config.layout` to your app layout name:

```ruby
RecordingStudioAttachable.configure do |config|
  config.layout = "application"
end
```

## Authorization and lifecycle behavior

By default, attachable delegates authorization checks to `RecordingStudioAccessible::Authorization.allowed?` using the configured role map.

Default roles:

- `view`: `:view`
- `upload`: `:edit`
- `revise`: `:edit`
- `remove`: `:admin`
- `restore`: `:admin`
- `download`: `:view`

Removal is Trashable-aware:

- if the child attachment recording responds to Trashable hooks, remove uses trash/restore operations
- otherwise the attachment recording is destroyed outright

## UI expectations

The engine ships with:

- an attachment listing page with scope and kind filters plus grid/list view toggles
- name search, pagination, and bulk remove from the attachment listing page
- an upload page with direct uploads, previews, progress, and server-side batch validation
- an attachment detail page for gallery/library metadata editing and download/trash actions
- an attachment file button for single-file parents (`max_file_count: 1`) that stays on the parent page via `return_to`

Host owns Turbo frames and Avatar. Attachable supplies the file button and a preview URL helper:

```erb
<%= turbo_frame_tag "page-avatar-attachment" do %>
  <div class="inline-flex items-end gap-3">
    <%= render FlatPack::Avatar::Component.new(
      src: attachment_preview_url(@recording),
      size: :"2xl",
      shape: :circle
    ) %>
    <%= render_attachment_file_button(@recording, return_to: page_path(@page)) %>
  </div>
<% end %>

<%= turbo_frame_tag "page-file-button" do %>
  <%= render_attachment_file_button(@recording, return_to: page_path(@page)) %>
<% end %>
```

Optional `target:` sets `data-turbo-frame` on the form (host frame id, or `"_top"`). Default inherits the enclosing frame. Optional `presentation:` is `:page` or `:modal`. Leave it out and the button uses `config.upload_presentation`.

Replace never navigates to the attachment details screen. Keep `attachments#show` for gallery/library cases where the attachment itself is the record.

### Upload in a modal

The standard upload page (multi-file queue, drag and drop, per-file progress, upload providers) can open in a FlatPack modal instead of navigating away. The full page stays the default.

```ruby
# config/initializers/recording_studio_attachable.rb
config.upload_presentation = :modal # default :page
```

Override it per button or per collection editor:

```erb
<%= render_attachment_file_button(@recording, return_to: page_path(@page), presentation: :modal) %>

<%= attachment_collection_editor(
      @section,
      association: :images,
      fields: [:caption, :credit, :alt_text],
      upload_button: { presentation: :modal, label: "Add images", target: "section-images" }
    ) %>
```

`AttachmentFileButton.locals(..., presentation: :modal)` takes the same option when a host renders the button partial itself.

- Only Add uses the modal. Change (replacing one file on a single-file parent) stays the inline file button.
- The modal body is a lazy turbo frame. The first open loads `attachments/upload?embed=upload_modal&frame_id=...` without a layout, page nav, or title. The page and the modal render `attachment_uploads/_uploader`. Hosts need Turbo (`@hotwired/turbo-rails`) on the page.
- After a successful upload the uploader dispatches a bubbling `attachable:uploaded` event (`event.detail.attachments`, `event.detail.redirectPath`) instead of redirecting. It clears its queue and closes the modal. The button then reloads `target:` when that id is a turbo frame on the page. Otherwise it re-visits the current page with Turbo, or reloads it when Turbo is missing.
- The standalone page still redirects to `return_to` after upload.
- Providers with `strategy: :modal_page` are left out of the modal, because that modal page cannot open inside the upload modal. Link providers open at the top level (`data-turbo-frame="_top"`). Client pickers such as Google Drive and Dropbox stay on the uploader.
- `upload_button:` takes `true` or a hash with `presentation:`, `label:`, and `target:`. Leave it out and the editor renders no Add button. The collection button always adds.

Wrap the editor in a turbo frame and pass that frame's id as `target:` when the list should refresh in place:

```erb
<%= turbo_frame_tag "section-images" do %>
  <%= attachment_collection_editor(
        @section,
        association: :images,
        fields: [:caption, :credit, :alt_text],
        upload_button: { presentation: :modal, target: "section-images" }
      ) %>
<% end %>
```

### Edit many images

`attachment_collection_editor` edits the direct images, files, or attachments on a parent and saves the rows that changed. Caption, credit, and alt use the same Flatpack fields. Nothing is written onto the blob. `:name` edits the existing name. There is no title column.

```ruby
attachment_collection_editor(
  @section,
  association: :images,
  fields: [:caption, :credit, :alt_text],
  displays: [:list, :carousel, :grid],
  default_display: :list,
  sortable: true
)
```

Leave `displays` out and the helper renders the list only, with no switch. That is the same screen as before. `displays` is the set, in switch order. `:list` is the rows side by side with their fields. `:carousel` slides the cards in the Flatpack carousel. `:grid` tiles the pictures and keeps each file's proportions. The switch labels are List, Slides, and Grid.

Each image sits in a card. On Slides, the picture moves into that card and the fields stay with the slide. Above those fields, the card shows the file name, then the type, the pixel size, and the file size when those are known. The tray around the cards has no border and no fill. Image thumbs sit under the carousel, one per card, and use the same preview. A gap separates one card from the next. The picture sits flush with the card edges, and the fields span the card beneath it. The next card peeks in when `side_preview` is on.

`default_display` must be one of `displays`. Leave it out and the first entry opens. `displays: [:carousel]` is slides only, with no switch. `displays: [:grid]` is the grid only, with no switch. An unknown display raises. A default that is not in the set raises.

The switch does not reload the page. List, Slides, and Grid keep separate copies of the fields. The list has one Save, and that save writes every row that changed, then the page reloads on the list. Each slide has its own Save, and that save writes that image without reloading the page. The slide you are on stays on screen, and its Save returns to the default button. Grid works the same way inside the edit modal: Save writes that image, the modal stays open, and the list and slide copies of that image pick up the saved text. Text typed on another slide or in another grid modal stays there. The picture moves between the list thumbnail and the slide. The grid tile is its own picture. Refreshing returns to `default_display`. The choice is not in the signed save token.

`sortable: true` reuses Orderable on that parent (`recording_studio_orderable_reorder!`) and splices this association into the parent's existing child order. This gem does not depend on `recording_studio_orderable`. Without that method, the helper raises. Omit `sortable` to keep newest-first and skip reorder. The drag handle and Order field show on List. A slide form and a grid form leave order out, so saving one image from Slides or Grid does not reorder the set. Reorder from List, then use the list Save.

Pass `items:` to edit a linked sheet instead of the parent's own files. Each entry is a recording, or an object that responds to `member` and `attachment_recording` when the row is not the file. Reorder writes the member ids. Caption, credit, alt text, name, and description still revise the file. `remove_label:` replaces Trash. `remove_path:` is a path string or a callable. A string may include `%{member_id}` and `%{attachment_id}`. A callable is `->(row, redirect_params) { ... }` and is snapshotted for the current members. `orderable_message:` replaces the error raised when a sortable parent does not list every member.

The signed save token stores `items:`, `remove_label:`, `remove_path:`, and `orderable_message:`. The default collection update URL reads them back, so the save does not need those options again. On save, each member is loaded from the signed id or GlobalID and must still belong to this parent. The file must still be an attachment, and its id must still match the signed id. A member from another parent, a swapped id, or a tampered token is rejected. `displays`, `default_display`, `side_preview`, `items_per_view`, and `preview` stay out of that token.

On Grid, each tile is the natural preview, even when `preview:` is `:square`. A short picture can leave space under it when the neighbor in that row is taller. Click a tile to edit that image. The modal is as tall as the original file and the fields. A tall picture grows the card, and you scroll the overlay to reach the fields. Save sits on the left. Trash is the icon on the right. Close the modal without saving and the text is still there the next time you open it. List and Slides still open the original file when you click a preview.

Click a preview to open the original file in a modal. That modal is as tall as the file, and you scroll the overlay when the file is taller than the screen. On the list, Trash sits under the fields as a red button. On a slide, Trash is the icon at the right of the fields, and Save sits on the left of that row. Slides uses the Flatpack carousel: its previous and next controls move between cards, its expand control opens the original, and a thumb under the tray jumps to that card. The dot indicators stay off. One image hides the previous and next controls. The thumb stays. Every slide keeps its own form, including the ones off to the side.

Save starts as the default button and is only as wide as its label. Change a caption, credit, alt text, name, or order and it turns primary. Put the fields back and it returns to default. That switch is Flatpack's unsaved-changes behavior on the save form. The host layout needs `flat_pack/application` so the primary colour paints. On Slides, typing in a field stays there: the space bar and arrow keys do not move the carousel.

`side_preview: true` peeks the next card on the right of the current slide. Omit it, or pass `false`, to keep each card full width. It is not in the signed save token.

`items_per_view` chooses how many cards are on screen. Omit it and one card shows at every width. Pass a whole number to use that count on mobile, tablet, and desktop. Pass `mobile:`, `tablet:`, and `desktop:` when the count should change with the width. Tablet starts at 768px and desktop at 1024px. A missing width stays at one. Zero, a fraction, and an unknown width raise. It is not in the signed save token.

`preview:` chooses the picture in the list and on Slides. The default `:square` uses the `square_med` crop. `preview: :natural` uses the `med` variant and keeps the file's proportions. On the list the picture stays about 208px wide beside the fields. On Slides the picture bleeds to the card edges. It stays tall enough for the previous and next controls, and it is capped in height. The fields span the width under it. Clicking those previews still opens the original file. Grid ignores `preview:` and always uses the natural `med` preview. `preview:` is not in the signed save token. An unknown value raises.

FlatPack is the default UI system for the engine and the dummy app (pinned to `v0.1.213` in the root Gemfile and the dummy app; gem requires `>= 0.1.213`).

## Development

The dummy app in `test/dummy` mounts both Recording Studio and this engine so you can validate upload/listing flows inside a realistic shell.

Dummy credentials (`test/dummy/config/credentials.yml.enc`) are encrypted with the shared RecordingStudio_* development master key. Set `RAILS_MASTER_KEY` or put that key in `test/dummy/config/master.key` (gitignored). Keep the encrypted file; do not generate a per-repo dummy key.

### Dummy app notes

- the dummy app is a validation shell, not a production template
- CI installs the dummy app bundle and runs dummy-app migrations before the root checks
- the dummy app pins RecordingStudio `v4.7.0`, Recording Studio Accessible `v0.15.0`, Recording Studio Orderable `v0.3.0`, Recording Studio API `v0.11.4`, RecordingStudio Google Drive `v0.2.0`, and RecordingStudio Oauth `v0.14.1`
- make sure engine, Active Storage, and Recording Studio tables are migrated in the dummy app before validating upload flows locally
- `bin/rails db:seed` attaches a twenty-shot Kiln canister press kit to the workspace. The shots mix portrait, square, and landscape frames. Edit images uses those files. Seeds also remove the colour-block stand-ins `window.jpg`, `dock.jpg`, and `pier.jpg` when they are still on the workspace.
- set `DUMMY_ACTIVE_STORAGE_SERVICE=amazon` plus `DUMMY_AWS_ACCESS_KEY_ID`, `DUMMY_AWS_SECRET_ACCESS_KEY`, `DUMMY_AWS_REGION`, and `DUMMY_AWS_BUCKET` to exercise S3-backed uploads in the dummy app; `DUMMY_AWS_BUCKET` may be either the plain bucket name or a bucket ARN
- optional `DUMMY_AWS_ENDPOINT` for Cloudflare R2 (or another S3-compatible API URL). When it is unset, the dummy `amazon` service keeps talking to AWS S3. When it is set, the dummy also uses `force_path_style: true` and checksum calculation/validation `when_required` (R2-safe).
- **Object storage (host Active Storage, not Attachable config):** this gem does not hard-code AWS S3 or Cloudflare R2. File blobs, direct uploads, and previews use whatever service the **host app** selects via `config.active_storage.service` and `config/storage.yml`. Attachable has no separate storage backend setting.
- **AWS S3:** configure Active Storage’s `S3` service in the host `storage.yml` (same shape as the dummy `amazon` entry). The dummy env vars above map to that block only.
- **Cloudflare R2 (S3-compatible):** use the same Active Storage `service: S3` entry with R2 API credentials and bucket name. Hosts typically also set `endpoint` to the account R2 S3 API URL (for example `https://<account_id>.r2.cloudflarestorage.com`), `region: auto`, and often `force_path_style: true`. Allow the app origin in the bucket **CORS** policy (`PUT`, `GET`, and headers direct upload and previews need) so browser uploads and image variants work. The dummy `amazon` service reads `DUMMY_AWS_*`, including optional `DUMMY_AWS_ENDPOINT`; when that endpoint is set it also uses `force_path_style` and checksums `when_required`. Host apps still configure `endpoint` / `force_path_style` in their own `storage.yml` when they point production or a custom env at R2.

  ```yaml
  # Host app config/storage.yml (example — not shipped by this gem)
  cloudflare_r2:
    service: S3
    access_key_id: <%= Rails.application.credentials.dig(:r2, :access_key_id) %>
    secret_access_key: <%= Rails.application.credentials.dig(:r2, :secret_access_key) %>
    region: auto
    bucket: your-bucket
    endpoint: https://<account_id>.r2.cloudflarestorage.com
    force_path_style: true
  ```

### CI-aligned validation

Run the same sequence CI uses when you touch dummy-app boot, assets, or migrations:

```bash
cd test/dummy
bundle install
bundle exec rake db:migrate RAILS_ENV=test

cd ../..
bundle exec rubocop
bundle exec rake test

cd test/dummy
bundle exec rails test
```

### Standard root validation

If your change does not affect the dummy app boot path, the standard root validation command is:

```bash
bundle exec rake test
```

## Cloud Agent boot

Cloud Agent Builds run `.cursor/install.sh`, then `.cursor/fetch-skills.sh`.
The install hook provisions a cold image. On a warm snapshot it skips apt,
ruby-build, db:prepare, and tailwind when Ruby, bundle, and Postgres are
already usable. If `RAILS_MASTER_KEY` is set, it writes gitignored
`test/dummy/config/master.key`. Fetch-skills always runs last. `.cursor/start.sh` starts
PostgreSQL on each boot. Rebuild with Draft off to load a new pack. See
[Cursor skills in Cloud Agents](docs/cursor-skills.md).
