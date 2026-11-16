# Recording Studio Attachable

Current development pins:

- `recording_studio` git tag `v7.3.0` (`>= 7.0, < 8.0`; API 1.2 needs `>= 7.1.0`)
- `flat_pack` tag `v0.1.377` (`FlatPack::VERSION` `0.1.377`, gemspec `>= 0.1.376`)
- `view_component` `4.19.0`
- `recording_studio_api` `>= 1.1.0, < 2.0` (Gemfile tag `v1.2.1`)
- `recording_studio_metrics` `>= 0.9.0, < 1.0` (Gemfile tag `v0.9.0`)

`RecordingStudioAttachable.configuration.layout` defaults to `nil`. The engine base controller calls `recording_studio_layout` with that setting. `nil` uses `RecordingStudio.configuration.layout`, then `"recording_studio/default_layout"`.

Accepted layout values are `nil`, `false`, a layout name, or a callable invoked as `call(controller:)`.

Bundler resolves the dummy app against the pinned GitHub release tags. Trashable `v1.0.1` allows Recording Studio `v7.3.0`. Oauth `v0.25.0` and Site Settings `v0.6.0` are the pins that resolve with API `v1.2.1`. The dummy initializer sets `config.authorize_write` so a write with an actor is allowed. The dummy schema includes Trashable `purge_at` and `recording_studio_events.root_recording_id`.

Gem pages set `content_for :title` and `:subtitle`, `flat_pack_page_nav` for back and close, and `register_page_nav` for page actions. The layout draws the shell. Modal and Turbo-frame responses still pass `layout: false`.

Library grid cards use `card.media(aspect_ratio: "4/3")`. The attachment page uses `card.media(aspect_ratio: "1/1")`. Broken previews, non-image files, and the empty library render `FlatPack::EmptyState`. The description field is `FlatPack::TextArea`.
