# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.5.0] - 2026-08-28

### Added
- Parent attachment slot for single-image parents (`max_file_count: 1`) with file-only replace/add controls that stay on the parent page
- `render_parent_attachment` helper and `GET /recordings/:recording_id/parent_attachment` frame endpoint
- Turbo Stream refresh of the parent attachment frame after file replace or first import when `redirect_mode=return_to`

### Changed
- `attachment_revision_upload_controller.js` now supports browse-triggered hidden file inputs, auto-submit, and import field names for parent-slot uploads
- File replacement through `PATCH /attachments/:id` redirects back to `return_to` when `redirect_mode=return_to` is present

### Upgrade Notes
- For profile photos, logos, and other single-image parents, render `render_parent_attachment(recording, return_to: parent_show_path)` on the parent show screen instead of linking replace flows to `attachments#show`.
- Pass `redirect_mode=return_to` and `return_to=<parent_show_path>` through the slot forms automatically via the helper; keep `attachments#show` for gallery/library metadata editing only.

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

[Unreleased]: https://github.com/bowerbird-app/RecordingStudio_attachable/compare/v0.5.0...HEAD
[0.5.0]: https://github.com/bowerbird-app/RecordingStudio_attachable/compare/v0.4.0...v0.5.0
[0.4.0]: https://github.com/bowerbird-app/RecordingStudio_attachable/compare/v0.3.0...v0.4.0
[0.3.0]: https://github.com/bowerbird-app/RecordingStudio_attachable/compare/v0.2.0...v0.3.0
[0.2.0]: https://github.com/bowerbird-app/RecordingStudio_attachable/compare/v0.1.1...v0.2.0
[0.1.1]: https://github.com/bowerbird-app/RecordingStudio_attachable/releases/tag/v0.1.1
[0.1.0]: https://github.com/bowerbird-app/RecordingStudio_attachable/releases/tag/v0.1.0
