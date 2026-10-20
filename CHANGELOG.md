# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.20.1] - 2026-10-20

### Changed

- Require `recording_studio_metrics` `>= 0.3.0, < 0.6` so hosts can use Metrics 0.4 and 0.5. `RecordingStudioAttachable::Metrics.register!` is unchanged.

### Upgrade Notes

- Bump to `0.20.1`. No migration.
- Pin `recording_studio_metrics` to `>= 0.3.0, < 0.6`. Latest Metrics is `v0.5.0`. The dummy app stays on Metrics `v0.3.1` because `recording_studio_api` `v0.11.4` and `recording_studio_trashable` `v0.11.1` still require Metrics `< 0.4`.

## [0.20.0] - 2026-10-16

### Added

- Recording Studio API actions `create_upload`, `attach`, and `import_attachment` on the `:attachable` capability. `RecordingStudioAttachable::Api.register!(apis: [:public, :operations])` registers them on each named API when `RecordingStudioApi` is loaded. A host still lists the action names in `capability_actions` for each parent type.
- `create_upload` checks the parent's content types and max file size, the pending-upload cap, and storage capacity, and returns a direct-upload ticket (`signed_blob_id`, `upload.url`, `upload.headers`, `expires_at`).
- `attach` records one signed blob or a list through `RecordAttachmentUpload` / `RecordAttachmentUploads`, including caption, credit, and alt text. The signed id is purpose `:attachable_upload`, bound to the parent recording and actor, and refused once the blob is attached. The bytes are sniffed and must match the declared type.
- `import_attachment` fetches an HTTPS URL with `SafeRemoteFetch` and records it through `ImportAttachment`. `config.import_allowed_hosts` is the host allowlist (default empty). The declared type is kept and checked against the sniffed bytes.
- `PurgeUnattachedBlobsJob` deletes unattached blobs this gem tagged, older than `config.unattached_blob_ttl` (default 24 hours), when `config.purge_unattached_blobs` is true.
- Browser uploads use the recording direct-upload route. File responses stream, force a download outside PNG, JPEG, GIF, WebP, and PDF, and send a sandbox content security policy. `image/svg+xml` is excluded from `image/*` unless the allow list names it.
- `config.direct_upload_expires_in` (default 5 minutes) and `config.pending_upload_limit` (default 20).
- Safe remote fetch blocks `2002::/16` and every IPv4-mapped IPv6 address. A cross-host redirect drops the caller's headers.

### Upgrade Notes

- Bump to `0.20.0`. No migration.
- Install `recording_studio_api` and call `RecordingStudioAttachable::Api.register!` (pass named admin APIs when those clients should upload too). Add `create_upload`, `attach`, and `import_attachment` to `capability_actions` on each parent type. Include `RecordingStudioApi::ApiClient` in Accessible `access_actor_types`.
- Set `config.import_allowed_hosts` before calling `import_attachment`. An empty list rejects every URL.
- Set `config.purge_unattached_blobs = true` and schedule `RecordingStudioAttachable::PurgeUnattachedBlobsJob`. The job only deletes blobs this gem tagged.
- Point browser direct uploads at `recording_direct_uploads_path(recording)`. A signed id from `/rails/active_storage/direct_uploads` will not attach.
- `image/*` no longer allows `image/svg+xml`. Add that type explicitly to allow it. Imported files must declare the type Marcel sniffs from the bytes.
- `config.direct_upload_expires_in` replaces Active Storage's service URL expiry for these tickets. `config.pending_upload_limit` caps waiting uploads per actor and root.
- Browser uploads to S3 need a bucket CORS rule that allows `PUT` and the headers `Content-Type`, `Content-MD5`, and `Content-Disposition`. Other clients do not.
- Google Drive and Dropbox tokens live in the Rails session. Use the encrypted cookie store (the Rails default) or another encrypted server-side store.
- `signed_blob_id` and `checksum` are filtered from request logs. This gem does not log the upload URL.

## [0.19.0] - 2026-10-16

### Changed

- Require `recording_studio_metrics` `>= 0.3.0, < 0.4` (GitHub tag `v0.3.1`).
  `RecordingStudioAttachable::Metrics.register!` is unchanged: it still
  registers `:attachments` with `api_authorize` via
  `RecordingStudioAttachable::Api::Access.can_view?`. The host still calls
  `RecordingStudioMetrics::Api.register!(api: :operations)`.

### Added

- README and install notes name the RecordingStudio MCP `0.17.0` tools
  (`attachments-storage_used`, `attachments-uploads_over_time`,
  `attachments-by_kind`, `attachments-by_content_type`). `from`, `to`, and
  `interval` apply only to `attachments.uploads_over_time`.

### Upgrade Notes

- Bump to `0.19.0`. No migration.
- Pin `recording_studio_metrics` to `>= 0.3.0, < 0.4` (tag `v0.3.1`).
- RecordingStudio MCP `0.17.0` advertises one tool per exposed metric. No
  extra register call in this gem.

## [0.18.0] - 2026-10-13

### Removed

- Image libraries and placements. `Library`, `Placement`, `ImageLibrary`, `LibraryPlacement`, `library_for`, placement routes, and `association: :placements` now belong in the Recording Studio library gem. Attachable no longer knows about them.
- Gem migrations for `recording_studio_attachable_libraries` and `recording_studio_attachable_placements`.

### Changed

- The collection editor still edits direct images, files, and attachments (List, Slides, Grid). A caller can pass `items:` whose member recording is not the file, plus `remove_label:`, `remove_path:`, and `orderable_message:`. The signed save token stores those options, and the default update action reads them back.
- The migrations generator stamps each copied file one second after the previous file.
- Attachment show warns before trash only when `config.attachment_place_labels` returns labels. The default is none.
- The image picker's load error says "Unable to load images".

### Upgrade Notes

- Bump to `0.18.0`. No data migration. Recording Studio is not in production.
- Stop calling `library_for`, `ImageLibrary.to`, `LibraryPlacement.to`, `recording_library_path`, and `recording_placements_path`. Install the library gem for that behavior.
- Drop `Library` and `Placement` from `recordable_types`. Do not copy the removed migrations.
- `config.placement_place_label`, `config.placement_picker_libraries`, and `config.library_label` are gone. Set `config.attachment_place_labels` if the attachment page should warn that a file is in use.
- Collection editor `items:`, `remove_label:`, `remove_path:`, and `orderable_message:` travel in the signed save token. The default update URL uses them. A string `remove_path:` may include `%{member_id}` and `%{attachment_id}`. A callable is snapshotted for the members in `items:`.

## [0.17.0] - 2026-10-12

### Added

- Opt-in modal presentation for the standard upload page. `config.upload_presentation = :page | :modal` (default `:page`). `presentation:` on `render_attachment_file_button` and `AttachmentFileButton.locals`. `upload_button: { presentation:, label:, target: }` on `attachment_collection_editor`.
- In modal mode the Add button opens a FlatPack modal. A lazy turbo frame loads `attachments/upload?embed=upload_modal` without a layout. Change (replacing one file) stays the inline file button.
- `upload_modal_controller.js` sets the frame source on open. After upload it reloads the `target:` turbo frame, or the current page when no frame is named.
- `upload_controller.js` `successBehavior` (`redirect` or `event`). `event` dispatches a bubbling `attachable:uploaded` event, clears the queue, and closes the enclosing FlatPack modal.
- Unit, integration, and system tests. The dummy app's test group adds `capybara` and `selenium-webdriver`.

### Changed

- The upload page body moved into `attachment_uploads/_uploader.html.erb`. The page and the modal share it, including multi-file choose, drag and drop, and per-file progress.
- `upload_controller.js` looks up provider frames and modals inside its own element, so a page and a modal uploader can share one document. `provider-import-complete` messages for another uploader's modal are ignored. The CSRF token falls back to a value rendered on the uploader when the page has no `csrf-token` meta tag.
- In modal mode the uploader does not navigate the whole page after upload, and it leaves out `modal_page` providers.

### Upgrade Notes

- Bump to `0.17.0`. No migration. The default stays `:page`, so existing screens are unchanged.
- Hosts that open the uploader in a modal need Turbo on the page. Pass `target:` as a turbo frame id to refresh a list in place.
- Google Drive's picker inside the upload modal still needs a manual check. `modal_page` providers are omitted so a provider modal is not opened inside this one.

## [0.16.0] - 2026-10-12

### Added

- Cloud upload adapters: Google Drive and Dropbox are self-contained adapters on the existing upload-provider registry. Each has an explicit `enabled` switch and is registered only when enabled and fully configured.
- Dropbox adapter: OAuth 2.0 with PKCE, Chooser, server-side resolve via `files/get_metadata` and `files/download`. Copy into Active Storage only.
- Shared `RecordingStudioAttachable::SafeRemoteFetch` for adapter downloads: HTTPS only, per-adapter hosts, drop `Authorization` (case-insensitive) on cross-host redirects, pin the validated IP, block private/loopback/CGNAT/multicast addresses, refuse oversize before a full download, stream to a Tempfile with a byte cap, connect/read timeouts plus an overall deadline.
- Adapters register their own config objects. Hosts set `config.google_drive.*` and `config.dropbox.*` as before for Drive.

### Changed

- Google Drive no longer has special cases in core configuration, routes, requires, or Stimulus controllers. It mounts and registers itself through the adapter hooks.
- Google Drive downloads use the shared fetch. Cross-host redirects no longer reuse the Bearer token. File ids in Drive API paths are URL-encoded. Adapter launcher modules load through the string-argument `javascript_tag(..., nonce: true)` form so `import "..."` is not HTML-escaped.
- Drive and Dropbox share core adapter helpers (`SessionAccessToken`, client-picker registration, selection normalizing, JSON parse, OAuth form posts, import-selected-files).
- `SafeRemoteFetch` treats `max_file_size` `nil` as no byte cap. Deadlines and connect/read timeouts still apply.
- Drive and Dropbox bootstrap JSON returns `403` when the actor cannot upload (was `422` on Drive). Disabled adapters still return `422`. Connected Drive bootstrap includes `expires_at` so the browser can drop a near-expiry picker token.

### Fixed

- OAuth popup completion pages emit the postMessage payload as a JavaScript object literal so the script can run and close the window.
- Dropbox Chooser (`Dropbox.choose`) and OAuth popups run inside a user click. Bootstrap and `dropins.js` preload on connect/hover. After Drive OAuth, the Picker opens on its own (`setVisible` does not need a click). Dropbox does not auto-open Chooser after connect; the same Dropbox button opens `choose()` on the next click. Neither adapter adds a second Choose from… button.
- After OAuth completes, the cached picker bootstrap is dropped and fetched again so the same page opens the Chooser or Picker instead of a second sign-in. Drive also refetches when the picker `access_token` is within 30 seconds of expiry. A `403` or `422` bootstrap disables the provider button instead of leaving an uncaught rejection. Turbo-cached reconnect rebinds prefetch listeners.
- Dropbox import URLs use `recording_studio_attachable.recording_attachment_imports_path` so host pages that render the gallery modal do not 500.
- Disconnected bootstrap returns a local `connect_url` and does not write OAuth state, so parallel Dropbox and Drive prefetch cannot clobber a cookie session. State is created on the connect click.
- Dropbox Chooser selections send the real filename. Import infers MIME type from that name instead of `application/octet-stream`, which the shared imports endpoint rejected for image libraries.

### Upgrade Notes

- Bump to `0.16.0`. No migration.
- Google Drive stays off by default. Hosts that already set `config.google_drive.enabled = true` plus OAuth and Picker credentials keep the Drive button. `config.google_drive.*` is unchanged.
- Dropbox is off until you set `config.dropbox.enabled = true` and credentials. Create a Dropbox app with redirect URI `/recording_studio_attachable/dropbox/oauth/callback` and scopes `files.metadata.read` and `files.content.read`. Add this host to Chooser/Saver domains in the Dropbox app.
- Adapter OAuth tokens stay in the Rails session. Hosts that enable both Drive and Dropbox should use a server-side session store (Redis, cache, or Active Record) so the browser’s 4 KB cookie limit is not hit.
- Custom `register_upload_provider` callers are unchanged. Optional `allowed_payload_keys` strips remote import payloads; omit it to keep the previous pass-through.

## [0.15.0] - 2026-10-12

### Added

- English Rails I18n keys for non-view copy under `recording_studio.attachable` (controller flashes, validation messages, collection empty/remove labels, field labels at render, file-fact type labels, Google Drive user-facing errors, and JS string blobs).
- Host English override coverage: test-only fixture `test/dummy/test/locales/attachable_host_override.en.yml` loaded via `I18n.backend.load_translations` (no `I18n.load_path` mutation) plus a real-page assert.
- Always-loaded boot-order guard `test/dummy/config/locales/recording_studio_attachable_host.en.yml` for a rarely shown flash key, with a render assert on the not-found redirect.
- Locale regression: every `lib/**/*.rb` file must not mention `i18n.load_path` / `I18n.load_path`.
- Render-level asserts for library empty title and upload page English.

### Changed

- Controller flashes, validation messages, Google Drive user-facing errors, and JS string blobs resolve through `Copy.t` / `Copy.legacy_t` with English `default:`.
- Public model/helper return values stay main's literal English (`Placement#title`, `AttachmentFileFacts#type_label`, collection `empty_message` / `remove_label`, STALE_FORM / GONE raises). Views keep main's conditional structure and swap only gem literals (or value expressions) to `t`/`Copy` with English `default:` — no new presence checks or branches.
- Validation `errors.add` for former English-string types passes the translated string as the String type (ActiveModel 8.1 ignores `message:` for Strings). In non-English locales, `errors.details` carries the translated string for those former String types.
- JS upload, picker, and collection-display controllers read copy from a data-attribute JSON blob with English fallbacks in JS (picker keeps the pre-existing `Select one or more` wording).

### Upgrade Notes

- Bump to `0.15.0`. No migration.
- English hosts need no change. Copy new `recording_studio.attachable.flashes.*`, `errors.*`, `collection.*`, `file_facts.*`, `google_drive.*`, `js.*`, and related keys into host locale files when translating.
- Hosts override by defining the same nested keys in their own `config/locales`. Public constants and public English-returning methods stay byte-identical to main; translate only at render.
- `AttachmentCollectionDisplay::LABELS` stays English at the constant (public API); views already translate display pills via nested keys.
- Metrics DSL titles stay English (captured at registration).

## [0.14.1] - 2026-10-09

### Fixed

- Site-wide attachment metrics resolve the admin root through `site_admin_recording_resolver` when that callable is set, and through `access_recording_resolver` otherwise.
- When resolving that admin root raises, `RecordingStudioAttachable::Api::Access.can_view?` denies access. Metrics discovery stays up.

### Upgrade Notes

- Bump to `0.14.1`. No migration.
- A host that sets `site_admin_recording_resolver` now uses it for attachment metrics. `access_recording_resolver` is only the fallback.
- A resolver error is treated as no access. The view check is still Recording Studio Accessible on the resolved admin root.

## [0.14.0] - 2026-10-09

### Added

- Site-wide attachment metrics register with Recording Studio Metrics for the
  operations API. `RecordingStudioAttachable::Metrics.register!` registers an
  `:attachments` resource (`blast_radius: :site`) with RecordingStudioMetrics.
  Metrics: `attachments.storage_used` (sum of `byte_size` on live current
  snapshots), `attachments.uploads_over_time`, `attachments.by_kind`
  (`attachment_kind`), and `attachments.by_content_type`. Counts and sums go
  through `RecordingStudio::Recording` (`recordable_type` + `trashed_at: nil`)
  joined to the current `recordable_id`, so revisions and the raw attachment
  table are not double-counted.
- `api_authorize` uses `RecordingStudioAttachable::Api::Access.can_view?`
  (AdminRoot `:view` via Recording Studio Accessible). The gem only registers
  metrics. The host calls `RecordingStudioMetrics::Api.register!(api: :operations)`.

### Upgrade Notes

- Bump to `0.14.0` and add `recording_studio_metrics` `~> 0.2` (GitHub tag
  `v0.2.0`).
- In the host, call `RecordingStudioMetrics::Api.register!(api: :operations)`
  after configuring the operations API. This gem does not register API
  endpoints.
- No migration. No logging or table changes.

## [0.13.0] - 2026-10-09

### Added

- English Rails I18n keys for static interface copy in the gem's own views,
  partials, layout, and Google Drive import screen (`config/locales/en.yml`
  under `recording_studio.attachable`)

### Changed

- Hard-coded buttons, labels, headings, empty states, aria-labels, placeholders,
  and hints in gem views resolve through `t("recording_studio.attachable.*")`
  (English output unchanged)

### Upgrade Notes

- No migration or host code change is required for English.
- Existing top-level keys in `config/locales/recording_studio_attachable.en.yml`
  (`recording_studio_attachable.*`) and their callers are unchanged.
- To translate or override the new defaults, add keys under
  `recording_studio.attachable` in the host's locale files.
- There is no dependency on `recording_studio_internationalization`.

## [0.12.0] - 2026-10-09

### Added
- Host-mounted image libraries. `RecordingStudioAttachable::Library` is a first-class child under a parent that enables `ImageLibrary.to` (a root, or a brand / client / project). Access follows Accessible. People upload and edit photos. They do not create, title, rename, or browse libraries.
- `library_for(parent)` find-or-creates one library per parent (`key: "default"`). Extra libraries in the same parent use a host key, for example `library_for(parent, key: :campaign)`, idempotent per parent and key. The label comes from i18n or `config.library_label`.
- Mount the existing listing with `library_path_for(library)` or `library_path_for(parent, key: :campaign)` / `recording_library_path`. There is no Attachable-owned libraries index or nav entry.
- `RecordingStudioAttachable::Placement` points a host page at a photo in any live library in the same workspace and reuses Orderable for position. Caption, credit, and alt stay on the photo. Cross-workspace and non-library photos are refused.
- The add-from-library picker uses the libraries the host passes in `placement_picker_libraries`. The switcher shows only when that list has more than one. The default list is the default library for the nearest `ImageLibrary` parent.
- Trashing a library with in-use photos shows the same in-use warning with rolled-up counts. Permanently deleting a library or a photo removes its placements. Removing a placement never deletes the photo. Trashed photos stay pointed at and are skipped when resolving.
- Dummy app: the host mounts Images and Campaign in its own nav. The Gallery places a photo from each.
- Placements reuse `attachment_collection_editor`. Pass `association: :placements` and the resolved placements. The host page keeps Add from library, Upload, list reorder, and Remove from here. Caption, credit, and alt use the same Flatpack fields as a direct image editor. Saving writes those on the library photo.

### Changed
- Collection editor list, slides, and grid match the main markup for both direct images and placements. The drag handle is icon-only. Order is a hidden input. Grid tiles are the original preview buttons.

### Upgrade Notes
- Bump to `0.12.0` and run `rails generate recording_studio_attachable:migrations` then `db:migrate`. That adds `recording_studio_attachable_libraries` (`key`) and `recording_studio_attachable_placements`.
- Add `RecordingStudioAttachable::Library` and `RecordingStudioAttachable::Placement` to `config.recordable_types`.
- Enable `include RecordingStudio::Capabilities::ImageLibrary.to` on each parent that should hold libraries (the root, or a brand / client / project). Enable `include RecordingStudio::Capabilities::LibraryPlacement.to` on host types that should hold library photos.
- Reorder needs Recording Studio Orderable on the placement parent (`allows: ["RecordingStudioAttachable::Placement"]`).
- Provision libraries in host code with `library_for`. Mount each one in the host nav. Do not send people to a libraries index.
- Pass picker libraries with `config.placement_picker_libraries`. One library means no switcher.
- Presskits and other hosts that still attach files under a section should move to placements in a follow-up. Existing direct attachments are unchanged.
- See [docs/image-library.md](docs/image-library.md).

## [0.11.0] - 2026-10-09

### Changed
- Image modals use Flatpack `scroll: :page`. The edit modal and the original-file modal grow with the picture. You scroll the overlay to see the rest. The picture is no longer capped at 70vh.
- Requires Flatpack `>= 0.1.213`. The root Gemfile and the dummy app pin tag `v0.1.213`.

### Upgrade Notes
- Update Flatpack to `0.1.213` or newer. Rebuild host Tailwind so `sm:my-auto` is generated, and reload Flatpack CSS and JavaScript.
- Upload and library-picker modals stay a fixed height. They hold an iframe or a scrolling library, and they still scroll inside the card.
- No migration.

## [0.10.0] - 2026-10-08

### Added
- `attachment_collection_editor` accepts `:grid` in `displays`. Grid tiles the pictures at their own proportions. Click a tile to edit that image in a modal. Save writes that image and leaves the modal open. Omit `:grid` to keep the list and slides as they are.
- The dummy Edit images press kit is twenty shots of the Kiln canister, mixing portrait, square, and landscape frames.

### Upgrade Notes
- Pass `displays: [:list, :carousel, :grid]` when the host should offer Grid. The switch label is Grid. `displays: [:grid]` is the grid alone, with no switch.
- Grid uses the natural preview even when `preview:` is `:square`. List and Slides still follow `preview:`.
- A grid save does not reload the page and does not open the list. The list save still reloads. A grid save leaves order out, so it does not reorder.
- No migration.

## [0.9.0] - 2026-10-08

### Added
- `config.url_mode` (`:rails` default, or `:direct`) chooses how attachment delivery URLs are built. Studio UI helpers keep the authorized Rails path unless the host sets `:direct`.
- `config.direct_url_host` for public custom-domain links (for example `images.featuredin.press`). Direct URLs are `https://<direct_url_host>/<blob key>` with no expiry and no presigning.
- `Attachment#original_url(mode:, rails_url:)` and `Attachment#url_for_variant(variant_name, mode:, rails_url:)` with a per-call `mode:` override.
- `config.preprocessed_variants` and `PreprocessVariantsJob`, enqueued after an attachment commit, so common sizes exist before direct delivery asks for them.
- Host-added custom names in `config.image_variants` (for example `:poster`) are kept alongside the gem defaults. The default preprocessed set is `%i[small med large]` plus those host-added names, resolved at read time. Assigning `preprocessed_variants` is an exact override.

### Changed
- Direct mode for a resize always uses the processed variant's own Active Storage blob key (the `variant_record` image key), never the original blob key.
- When direct mode would return a URL for an unprocessed variant, the gem falls back to the authorized Rails preview path and enqueues preprocessing. That keeps correct dimensions (unlike falling back to the original's direct URL) and still lets the next request use a public variant key once processing finishes.
- `config.image_variants=` accepts host-added custom variant names. Previously unknown keys were ignored.

### Upgrade Notes
- Default `url_mode` is `:rails`. Existing hosts keep today's authorized engine paths with no config change.
- To serve public R2/custom-domain links, set both `config.url_mode = :direct` and `config.direct_url_host = "images.example.com"`. Calling `:direct` without a host raises `RecordingStudioAttachable::ConfigurationError`.
- Ensure Active Storage `track_variants` stays enabled (Rails 8.1 defaults do). Direct variant URLs read the variant_record image blob key.
- Default preprocessing is `small`/`med`/`large` plus any custom names you add under `image_variants`. Other gem defaults such as `square_med` or `xlarge` stay on-demand unless you list them in `preprocessed_variants`. Set `preprocessed_variants` when you want an exact list. Unknown override names are ignored. Non-image and unvariable files skip the job safely.
- Pass `rails_url:` when calling `original_url` / `url_for_variant` in `:rails` mode, or when `:direct` may need a fallback for an unprocessed variant. Engine helpers already pass the authorized path.

```ruby
RecordingStudioAttachable.configure do |config|
  config.url_mode = :direct
  config.direct_url_host = "images.featuredin.press"
  config.image_variants = { poster: { resize_to_limit: [1280, 720] } }
  # Optional exact override:
  # config.preprocessed_variants = %i[small med large poster]
end

attachment.url_for_variant(:med, mode: :direct, rails_url: preview_path)
attachment.original_url(mode: :rails, rails_url: file_path)
```

## [0.8.0] - 2026-10-07

### Added
- `attachment_collection_editor` can offer a list, slides, or both. Slides uses a Flatpack carousel. `items_per_view` chooses how many cards show at once. The picture sits flush with the card edges and stays tall enough for the previous and next controls. The fields span the card. Image thumbs sit under the carousel. The tray has no border and no fill. The list keeps one Save for every row. Each slide has its own fields and its own Save, and that save writes that image.

```erb
<%= attachment_collection_editor(
      recording,
      association: :images,
      fields: [:caption, :credit, :alt_text],
      displays: [:list, :carousel],
      default_display: :list
    ) %>
```

### Changed
- Requires Flatpack `>= 0.1.205`. The root Gemfile and the dummy app pin tag `v0.1.205`.
- Save on the image editor starts as the default button and is only as wide as its label. It turns primary when a caption, credit, alt text, name, or order differs from the saved values, and returns to default when those fields match again.
- Dummy and blank layouts load `flat_pack/application` so Flatpack button colours paint.
- On Slides, typing in a field stays in that field. Arrow keys and the space bar do not move the carousel.
- On Slides, an image thumb sits under the carousel for each card and uses that card's preview. The carousel tray has no border and no background. The dot indicators stay off.
- On Slides, each card shows the file name, type, pixel size, and file size above the fields when those are known. The list does not.
- Saving a slide stays on that slide. The page does not reload, and the list does not open. The list copy of that image picks up the saved text. A list save still reloads.
- The dummy Edit images screen seeds a four-shot Kiln canister press kit. Colour-block stand-ins are removed when seeds run.

### Upgrade Notes
- Update Flatpack to `0.1.205` or newer. Pill calls that leave out `style:` stay on the pill tokens. A CSS string in Tabs `style:` raises. Importmap apps that already eager-load Flatpack controllers pick up `flat-pack--unsaved-changes` with that gem.
- On Slides, the carousel tray no longer draws a border or a fill, and image thumbs appear under the cards.
- Save on `attachment_collection_editor` is no longer primary on arrival. Flatpack switches it to primary after a field changes.
- Omit `displays` to keep the list, with no switch. No migration.
- Pass `displays: [:list, :carousel]` when the host should offer both. `default_display` picks the one that opens and must be in that list. Leave it out and the first entry opens.
- Pass `displays: [:carousel]` for slides only.
- The display is not part of the signed save token. Refreshing returns to `default_display`.
- On Slides, the Flatpack carousel moves between cards. Each slide has its own copy of the fields and its own Save. Saving a slide does not reload the page and does not open the list. The list keeps one Save for every row, and that save still reloads. The picture moves between the list thumbnail and the slide. A slide save leaves order out, so it does not reorder. Reorder from List, then use the list Save. On a slide, Trash is the icon at the right of the fields. The file name, type, pixel size, and file size sit above the fields when they are known. The picture is flush with the card, the fields span the card, and a gap separates one card from the next. Image thumbs under the tray jump to a card. The tray has no border and no fill. Expand opens the original.
- Pass `side_preview: true` to peek the next card. Omit it to keep each card full width. It is not in the signed save token.
- Pass `items_per_view:` to choose how many cards show. A whole number applies at every width. A hash can set `mobile:`, `tablet:`, and `desktop:` separately. Omit it to keep one card. It is not in the signed save token.

## [0.7.3] - 2026-10-06

### Added
- Dummy `amazon` Active Storage service can point at Cloudflare R2 via optional `DUMMY_AWS_ENDPOINT`, with `force_path_style: true` and checksums `when_required`. Unset endpoint still uses AWS S3.

## [0.7.0] - 2026-10-02

### Added
- `attachment_collection_editor` edits the direct images, files, or attachments on a parent in one save. Caption, credit, and alt text are nullable text columns on the attachment snapshot. `:name` edits the existing name. There is no title column. Clicking a preview opens the original file in a modal.
- `preview:` chooses the row image. The default `:square` uses the `square_med` crop. `:natural` uses the `med` variant and keeps the file's proportions. The modal still opens the original file. `preview:` is not part of the signed save token. An unknown value raises.

```erb
<%= attachment_collection_editor(
      recording,
      association: :images,
      fields: [:caption, :credit, :alt_text],
      sortable: true,
      return_to: page_path(page)
    ) %>
```

### Upgrade Notes
- Run `rails generate recording_studio_attachable:migrations` and migrate. Attachment rows gain nullable `caption`, `credit`, and `alt_text`. No backfill. Do not look for a title column.
- Mount `attachment_collection_editor` where a host edits many images. Pass `:name` to edit the existing name, or `:description` for the existing description.
- `sortable: true` needs Orderable on that parent (`recording_studio_orderable_reorder!`). This gem does not depend on `recording_studio_orderable`. Without that method, the helper raises.
- Trash from the editor returns to `return_to` when the link sends `redirect_mode=return_to`. Other trash links stay on the library.
- Trash in the editor sits under the fields. It is a danger button labeled Trash, with a trash icon. The attachment page and the library list still use an icon button. Each trash control submits its own delete form.
- Pass `preview: :natural` when a row should show the file's proportions. Omit `preview` to keep the square crop. No migration.
- Detail save and file replace keep the new columns. A name-only save does not clear them. Existing `attachment[name]` / `attachment[description]` forms stay valid.

## [0.6.1] - 2026-10-01

### Added
- README: host Active Storage notes for AWS S3 and Cloudflare R2 (S3-compatible `storage.yml`, CORS); no Attachable-specific storage backend.

### Changed
- FlatPack `Button` call sites (including link-strategy `UploadProvider#button_options`) use `href:` instead of the obsolete `url:` kwarg from FlatPack 0.1.135. UploadProvider’s domain `url:` constructor stays unchanged.

## [0.6.0] - 2026-10-01

Optional storage cap for one root recording. Uploads stay unchanged until a host sets `config.storage_limit`.

### Added
- `config.storage_limit` names a Stripe quantity limit for retained bytes on one root. A blank value does not check capacity. This gem does not depend on `recording_studio_stripe`.
- `RecordingStudioAttachable.storage_bytes_for(root)` sums distinct original file blobs stamped with that root. Variant files are not included.
- Migration adds `root_recording_id` on attachment rows and backfills it from live recordings and events.

### Changed
- Trash and restore leave retained files in place, so usage stays the same. `Recording#destroy!` detaches those file rows and purges a blob that no other attachment still references.
- `StorageLimitUnknown` and `StorageLimitError` inherit `RecordingStudioAttachable::Error`. Services re-raise them.

### Upgrade Notes
- Run `rails generate recording_studio_attachable:migrations` and `rails db:migrate` so attachment rows gain `root_recording_id`.
- Leave `config.storage_limit` unset to keep the previous upload path.
- Set `config.storage_limit` to the host's Stripe quantity limit name when a root should refuse a write that does not fit. The product stores the cap as `limit_<name>`.

## [0.5.1] - 2026-09-02

Cloud Agent Builds fetch Cursor skills at install. A warm snapshot skips apt and still fetches the pack.

### Added
- `.cursor/install.sh`, `.cursor/start.sh`, `.cursor/environment.json`, and `.cursor/fetch-skills.sh`. Install provisions a cold image. Warm snapshot skips apt, ruby-build, db:prepare, and tailwind when Ruby, bundle, and Postgres are already usable. A skippable provision failure does not fail the Build. Fetch-skills always runs last. `.cursor/start.sh` starts PostgreSQL on each boot.

### Upgrade Notes
- No host or schema changes. Rebuild the Cloud Agent environment with Draft off so Build loads the pack.

## [0.5.0] - 2026-08-28

### Added
- `render_attachment_file_button(recording, return_to:, target: nil)` — Flatpack secondary Add/Change button with hidden file pick, direct upload, and auto-submit. Does **not** wrap a Turbo frame; optional `target:` sets `data-turbo-frame`
- `attachment_preview_url(recording, variant: :square_med)` so hosts can set Flatpack Avatar `src` for the parent's first file
- On file replace/import success with `redirect_mode=return_to`, responds with **303 See Other** to `return_to` (flash "File updated"); failures redirect to `return_to` with alert

### Changed
- Requires Flatpack `>= 0.1.135` (dummy pins `v0.1.135`)
- Host owns Turbo frames and Avatar composition; Attachable only supplies the file button + preview URL

### Removed
- `render_attachment_image_slot`
- `render_parent_attachment` and aliases
- Attachable-owned `turbo_frame_tag` wrappers and `turbo_stream.replace` of chrome partials
- Chrome identity hidden fields (`attachment_chrome[...]`)
- `GET /recordings/:recording_id/parent_attachment` product endpoint

### Upgrade Notes
- Replace any previous parent-slot helpers with host-owned frames, for example:

```erb
<%= turbo_frame_tag "profile-photo" do %>
  <%= render FlatPack::Avatar::Component.new(src: attachment_preview_url(@recording), size: :xl, shape: :circle) %>
  <%= render_attachment_file_button(@recording, return_to: user_path(@user)) %>
<% end %>
```

- Optional `target:` on the button sets `data-turbo-frame` when the form is outside the frame or should target `"_top"`
- Keep `attachments#show` for gallery/library metadata editing only

## [0.4.0] - 2026-08-21

### Changed
- `RecordingStudio::Capabilities::Attachable.to` is now a thin wrapper around `RecordingStudio::Capabilities.include_for(:attachable, **options)`
- Runtime dependency is now RecordingStudio `~> 4.2` (tested with `4.2.0`)
- Dummy and development bundles pin RecordingStudio `v4.2.0`
- Dummy sign-in layout no longer uses a squished `mt-28` / `fixed inset-0` shell

### Upgrade Notes
- Host apps already using `include RecordingStudio::Capabilities::Attachable.to(...)` do not need to change that verb.
- This gem now requires RecordingStudio `~> 4.2`. Stay on `0.3.x` if you are still on RecordingStudio `4.1`.
- Installing the gem still does not enable `:attachable`. Opt each parent recordable in with `.to`. Parent rules stay on `recording_studio_recordable`.
- `register_capability` still runs at engine boot. Do not call it from `.to`.

## [0.3.0] - 2026-08-20

### Changed
- Runtime dependency is now RecordingStudio `~> 4.1` (tested with `4.1.0`)
- Dummy and development bundles pin RecordingStudio `v4.1.0` and Recording Studio Accessible `v0.6.0`
- Dummy app installs the RecordingStudio 4 harden / unique-root indexes
- Dummy workspace enables `:accessible` and seeds admin access through `RecordingStudioAccessible.grant_access`
- Dummy app no longer bundles Recording Studio Trashable while that addon still requires RecordingStudio 3

### Upgrade Notes
- Host apps must move to RecordingStudio `~> 4.1` with this gem. Stay on `0.2.x` if you are still on RecordingStudio 3.
- Run `bin/rails generate recording_studio:migrations` and `bin/rails db:migrate` so the 4.0 harden / unique-root indexes are installed. Resolve duplicate root recordings before the unique index is created.
- Follow RecordingStudio 4.0 upgrade notes for implicit recording order (use `.recent` or an explicit `order:`) and append-only events.
- Prefer `config.require_actor = true` (and optionally `authorize_write` / `max_metadata_bytes`) in production hosts.
- Do not enable `:attachable` on a shared root. Enable it on domain children beneath that shared root, the same way Accessible 0.6 treats shared roots.
- If you use Recording Studio Accessible 0.6+, configure `config.access_actor_types` and create grants with `RecordingStudioAccessible.grant_access`.
- Restore still uses Trashable hooks when that addon is present. Trashable itself still requires RecordingStudio 3, so keep restore optional until a 4.x Trashable release exists.

## [0.2.0] - 2026-06-05

### Breaking
- Upgraded RecordingStudio support to `3.0.0`, including declaration-based recordable hierarchy requirements and capability-derived attachment parent allowances.

### Changed
- Bumped the dummy app FlatPack dependency from `0.1.41` to `0.1.49`
- Refreshed the root documentation to match the current gem setup, query API, and repository links

### Added
- Added a FlatPack TipTap attachment-image addon, reusable image picker endpoint, and dummy app integration for inserting recording-scoped images inline in rich text editors

## [0.1.1] - 2026-04-28

### Changed
- Bumped the dummy app FlatPack dependency from `0.1.2` to `0.1.33` and pinned it by tag in `test/dummy/Gemfile`

## [0.1.0] - 2025-12-04

### Added
- Initial release
- Rails mountable engine structure
- PostgreSQL with UUID primary keys support
- TailwindCSS v4 integration
- GitHub Codespaces devcontainer configuration
- Docker Compose setup with PostgreSQL and Redis
- Install generator for host applications
- Comprehensive README and documentation
- Basic test suite with Minitest

[Unreleased]: https://github.com/bowerbird-app/RecordingStudio_attachable/compare/v0.16.0...HEAD
[0.16.0]: https://github.com/bowerbird-app/RecordingStudio_attachable/compare/v0.15.0...v0.16.0
[0.15.0]: https://github.com/bowerbird-app/RecordingStudio_attachable/compare/v0.14.1...v0.15.0
[0.11.0]: https://github.com/bowerbird-app/RecordingStudio_attachable/compare/v0.10.0...v0.11.0
[0.10.0]: https://github.com/bowerbird-app/RecordingStudio_attachable/compare/v0.9.1...v0.10.0
[0.9.0]: https://github.com/bowerbird-app/RecordingStudio_attachable/compare/v0.8.0...v0.9.0
[0.8.0]: https://github.com/bowerbird-app/RecordingStudio_attachable/compare/v0.7.3...v0.8.0
[0.7.3]: https://github.com/bowerbird-app/RecordingStudio_attachable/compare/v0.7.2...v0.7.3
[0.7.0]: https://github.com/bowerbird-app/RecordingStudio_attachable/compare/v0.6.1...v0.7.0
[0.6.1]: https://github.com/bowerbird-app/RecordingStudio_attachable/compare/v0.6.0...v0.6.1
[0.6.0]: https://github.com/bowerbird-app/RecordingStudio_attachable/compare/v0.5.1...v0.6.0
[0.5.1]: https://github.com/bowerbird-app/RecordingStudio_attachable/compare/v0.5.0...v0.5.1
[0.5.0]: https://github.com/bowerbird-app/RecordingStudio_attachable/compare/v0.4.0...v0.5.0
[0.4.0]: https://github.com/bowerbird-app/RecordingStudio_attachable/compare/v0.3.0...v0.4.0
[0.3.0]: https://github.com/bowerbird-app/RecordingStudio_attachable/compare/v0.2.0...v0.3.0
[0.2.0]: https://github.com/bowerbird-app/RecordingStudio_attachable/compare/v0.1.1...v0.2.0
[0.1.1]: https://github.com/bowerbird-app/RecordingStudio_attachable/releases/tag/v0.1.1
[0.1.0]: https://github.com/bowerbird-app/RecordingStudio_attachable/releases/tag/v0.1.0
[0.14.1]: https://github.com/bowerbird-app/RecordingStudio_attachable/compare/v0.14.0...v0.14.1
[0.14.0]: https://github.com/bowerbird-app/RecordingStudio_attachable/compare/v0.13.0...v0.14.0
