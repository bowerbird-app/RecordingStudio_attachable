# Recording Studio Attachable

Current development pins:

- `recording_studio` git tag `v7.8.0` (`>= 7.0, < 8.0`). Hosts MUST run the Recording Studio 7.4, 7.5, and 7.7 migrations.
- `flat_pack` tag `v0.2.0` (`FlatPack::VERSION` `0.2.0`, gemspec `>= 0.1.376`)
- `view_component` `~> 4.19`
- `recording_studio_api` `>= 1.1.0, < 2.0` (Gemfile tag `v1.21.2`)
- `recording_studio_metrics` `>= 0.9.0, < 1.0` (Gemfile tag `v0.10.0`)

`RecordingStudioAttachable.configuration.layout` defaults to `nil`. The engine base controller calls `recording_studio_layout` with that setting. `nil` uses `RecordingStudio.configuration.layout`, then `"recording_studio/default_layout"`.

Accepted layout values are `nil`, `false`, a layout name, or a callable invoked as `call(controller:)`.

Bundler resolves the dummy app against the pinned GitHub release tags. Trashable `v1.3.0` allows Recording Studio `v7.8.0`. Oauth `v0.25.1` and Site Settings `v0.6.0` resolve with API `v1.21.2`. The dummy initializer sets `config.authorize_write` so a write with an actor is allowed. The dummy schema includes Trashable `purge_at`, `recording_studio_events.root_recording_id`, and API client `owner_type` / `owner_id`. Hosts MUST run the Recording Studio 7.4, 7.5, and 7.7 migrations. The dummy app does not copy those core migrations.

Gem pages set `content_for :title` and `:subtitle`, `flat_pack_page_nav` for back and close, and `register_page_nav` for page actions. The layout draws the shell. Modal and Turbo-frame responses still pass `layout: false`.

Library grid cards use `card.media(aspect_ratio: "4/3")`. The attachment page uses `card.media(aspect_ratio: "1/1")`. Broken previews, non-image files, and the empty library render `FlatPack::EmptyState`. The description field is `FlatPack::TextArea`.
