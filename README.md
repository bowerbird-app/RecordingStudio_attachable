# Recording Studio Attachable

Optional Recording Studio addon gem for uploading and managing images/files as child recordings beneath a recording.

## Highlights

- `RecordingStudio::Capabilities::Attachable.to(...)` opt-in API for parent recordables
- addon-owned `RecordingStudioAttachable::Attachment` recordable with `has_one_attached :file`
- child recording identity with append-only recordable revisions
- FlatPack-based listing, search, bulk remove, and upload UI slice
- Stimulus + Active Storage direct upload flow
- Accessible-backed authorization and Trashable-aware removal when available

## Requirements

- Ruby 3.3+
- Rails 8.1+
- Active Storage installed in the host app
- Recording Studio installed in the host app
- RecordingStudio Accessible installed for the default authorization adapter
- RecordingStudio Trashable installed if you want restore support for removed attachments

## Quick start

1. Add the gem to your host app.
2. Ensure Active Storage and RecordingStudio Accessible are installed.
3. Run `rails generate recording_studio_attachable:install`.
4. Run `rails generate recording_studio_attachable:migrations`.
5. Run `rails db:migrate`.
6. Register `RecordingStudioAttachable::Attachment` in `RecordingStudio.configure`.
7. Opt parent recordables into `RecordingStudio::Capabilities::Attachable.to(...)`.

## Host app setup

### 1. Add the gem

```ruby
# Gemfile
gem "recording_studio_attachable"
```

### 2. Register the attachment recordable

```ruby
RecordingStudio.configure do |config|
  config.recordable_types << "RecordingStudioAttachable::Attachment"
end
```

### 3. Opt a parent recordable into attachable

```ruby
class Workspace < ApplicationRecord
  include RecordingStudio::Capabilities::Attachable.to(
    allowed_content_types: ["image/*", "application/pdf", "text/plain"],
    max_file_size: 25.megabytes,
    max_file_count: 20,
    enabled_attachment_kinds: %i[image file]
  )
end
```

### 4. Mount the engine

The install generator adds the mount for you. The default mount path is:

```ruby
mount RecordingStudioAttachable::Engine, at: "/recording_studio_attachable"
```

### 5. Wire direct uploads

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

When browser-side image preprocessing is enabled, the gem's built-in direct-upload surfaces resize oversized JPEG, PNG, and WebP files before `DirectUpload` sends them to Active Storage. That includes the main upload page, the bundled attachment-image picker, and attachment file replacements on the revision screen. This is a best-effort optimization layer, not a security boundary: server-side content-type and byte-size validation still runs on the final uploaded blob. GIF, SVG, HEIC/HEIF, and other unsupported image types are uploaded unchanged.

For delivery, the engine uses a stable set of named image variants: `square_small`, `square_med`, `square_large`, `small`, `med`, `large`, and `xlarge`. Host apps can override the transformation sizes through `config.image_variants` while keeping those public names stable across engine views and integrations.

### Attachment image picker

The gem ships with a reusable image picker for browser-driven surfaces such as inline editors, chat composers, and custom attachment chips. The picker endpoint is `recording_attachment_picker_path(recording)` and always returns image attachments plus pagination metadata for the chosen parent recording.

In the browser, the bundled `recording-studio-attachable--attachment-image-picker` Stimulus controller loads that JSON into a FlatPack modal, supports search and direct uploads, and dispatches a `selected` event each time the user chooses an attachment. Consumers receive the selected attachment in `event.detail.attachment`.

```erb
<div
  data-controller="chat-demo recording-studio-attachable--attachment-image-picker"
  data-action="recording-studio-attachable--attachment-image-picker:selected->chat-demo#attachmentSelected"
  data-recording-studio-attachable--attachment-image-picker-picker-url-value="<%= recording_studio_attachable.recording_attachment_picker_path(@recording) %>"
  data-recording-studio-attachable--attachment-image-picker-upload-url-value="<%= recording_studio_attachable.recording_attachments_path(@recording) %>"
  data-recording-studio-attachable--attachment-image-picker-direct-upload-url-value="<%= main_app.rails_direct_uploads_path %>">
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
    import_url: ->(route_helpers:, recording:) do
      route_helpers.google_drive.recording_imports_path(recording, format: :json)
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
- `import_url`: JSON import handoff endpoint for `:client_picker`
- `launcher`: browser launcher name for `:client_picker`
- `modal_title`: optional modal heading for `:modal_page`
- `icon`, `style`, `size`, `target`: FlatPack button options
- `visible`: optional callable receiving `view_context:` and `recording:`

For `:modal_page`, the upload page opens the provider URL inside a shared FlatPack modal. The engine appends `embed=modal`, `provider_key`, and `provider_modal_id` to the provider URL so addon-owned screens can adapt their layout and communicate back to the upload page.

For modal-page providers, the shared browser contract is:

- the upload page opens the provider URL in an iframe modal
- addon screens can complete auth in a popup and post a `provider-auth-complete` message back to the upload page
- addon screens can post a `provider-import-complete` message with a `redirectPath` when the import succeeds

For `:client_picker`, the upload page stays in place and calls a registered browser launcher. The launcher fetches provider bootstrap JSON, can open auth in a popup, and can submit selected remote file ids back to the provider's `import_url`.

Client-picker launchers are registered in JavaScript:

```js
import { registerUploadProviderLauncher } from "controllers/recording_studio_attachable/provider_launchers"

registerUploadProviderLauncher("google_drive", {
  async launch({ controller, bootstrapUrl, importUrl }) {
    const bootstrap = await controller.fetchProviderBootstrap(bootstrapUrl)
    // open auth popup if needed, then launch provider SDK picker
    // finally post selected file ids back to importUrl
  }
})
```

In your provider controller or service, hand the gem an IO object plus metadata and let it create the blob, identify the file content by default, enforce attachable validations, and create the child recording:

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

Signed blob finalization with provider metadata:

```ruby
post recording_studio_attachable.recording_attachment_imports_path(recording), params: {
  attachment_import: {
    provider_key: "google_drive",
    attachments: [
      {
        signed_blob_id: blob.signed_id,
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

### Built-in Google Drive addon

This gem also ships with an optional Google Drive addon that uses the same provider discovery and import services described above. The addon stays dormant until you enable it and provide both OAuth and Google Picker credentials.

```ruby
RecordingStudioAttachable.configure do |config|
  config.google_drive.enabled = true
  config.google_drive.client_id = ENV.fetch("GOOGLE_DRIVE_CLIENT_ID")
  config.google_drive.client_secret = ENV.fetch("GOOGLE_DRIVE_CLIENT_SECRET")
  config.google_drive.api_key = ENV.fetch("GOOGLE_DRIVE_API_KEY")
  config.google_drive.app_id = ENV.fetch("GOOGLE_DRIVE_APP_ID")
  config.google_drive.redirect_uri = "https://your-app.test/recording_studio_attachable/google_drive/oauth/callback"
end
```

`GOOGLE_DRIVE_API_KEY` must be a browser API key for the same Google Cloud project, and `GOOGLE_DRIVE_APP_ID` is the Google Cloud project number used by Google Picker.

Once enabled, the upload page will automatically show a `Google Drive` provider button that opens Google auth and the Google Picker directly from the upload page. There is no provider-owned middle screen in the normal flow. The addon routes remain mounted inside the main engine at `/recording_studio_attachable/google_drive`.

The addon handles:

- Google OAuth browser handoff in a popup launched from the upload page
- bootstrap JSON for the built-in Google Picker launcher
- Google Picker selection directly from the upload page
- downloading selected files from Drive
- handing those files to `RecordingStudioAttachable::Services::ImportAttachments`

Imported files still go through the gem's normal authorization, blob identification, Active Storage validation, attachment creation, and recording creation flow. Native Google Docs formats are exported during import using Drive-compatible formats such as PDF, PNG, or CSV where supported.

Each import payload supports:

- `io`: readable IO object for the provider file
- `filename`: original filename to store in Active Storage
- `content_type`: MIME type used for validation and attachment kind classification
- `name`, `description`: optional attachment metadata overrides
- `actor`, `impersonator`: optional audit actors
- `source`: metadata source label stored on the recording event, defaults to `provider_import`; use this only in trusted direct service calls
- `metadata`: extra event metadata merged into the attachment upload event
- `identify`: optional Active Storage blob creation option. Defaults to `true`; only disable it in trusted integrations that already know the file metadata is accurate.

The HTTP endpoint accepts a single `attachment_import` envelope plus either:

- `file`: a multipart uploaded file that the engine should import into Active Storage
- `signed_blob_id`: an existing Active Storage blob id that the engine should finalize as an attachment

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

## Delivery

Attachment previews, editor insert URLs, and downloads are served through engine-owned endpoints so each request stays behind the gem's authorization checks. Host apps should link to the engine paths returned by the gem instead of generating raw Active Storage blob URLs for attachment delivery.

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

- an attachment listing page with scope and kind filters
- name search, pagination, and bulk remove from the attachment listing page
- an upload page with direct uploads, previews, progress, and server-side batch validation
- an attachment detail page for metadata revision and optional file replacement via direct upload

FlatPack is the default UI system for the engine and the dummy app.

## Development

The dummy app in `test/dummy` mounts both Recording Studio and this engine so you can validate upload/listing flows inside a realistic shell.

### Dummy app notes

- the dummy app is a validation shell, not a production template
- CI installs the dummy app bundle and runs dummy-app migrations before the root checks
- make sure engine, Active Storage, and Recording Studio tables are migrated in the dummy app before validating upload flows locally
- set `DUMMY_ACTIVE_STORAGE_SERVICE=amazon` plus `DUMMY_AWS_ACCESS_KEY_ID`, `DUMMY_AWS_SECRET_ACCESS_KEY`, `DUMMY_AWS_REGION`, and `DUMMY_AWS_BUCKET` to exercise S3-backed uploads in the dummy app; `DUMMY_AWS_BUCKET` may be either the plain bucket name or a bucket ARN

### CI-aligned validation

Run the same sequence CI uses when you touch dummy-app boot, assets, or migrations:

```bash
cd test/dummy
bundle install
bundle exec rake db:migrate RAILS_ENV=test

cd ../..
bundle exec rubocop
bundle exec rake test
```

### Standard root validation

If your change does not affect the dummy app boot path, the standard root validation command is:

```bash
bundle exec rake test
```
