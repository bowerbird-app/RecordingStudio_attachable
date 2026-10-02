# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

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

[Unreleased]: https://github.com/bowerbird-app/RecordingStudio_attachable/compare/v0.7.0...HEAD
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
