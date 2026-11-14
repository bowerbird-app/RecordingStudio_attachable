# Recording Studio Attachable

Current development pins:

- `recording_studio` git tag `v6.7.1` (`>= 6.7.1`)
- `flat_pack` tag `v0.1.356` (`FlatPack::VERSION` `0.1.356`, gemspec `>= 0.1.315`)
- `view_component` `4.19.0`
- `recording_studio_metrics` `>= 0.3.0, < 1.0` (Gemfile tag `v0.8.0`)

`RecordingStudioAttachable.configuration.layout` defaults to `nil`. The engine base controller calls `recording_studio_layout` with that setting. `nil` uses `RecordingStudio.configuration.layout`, then `"recording_studio/default_layout"`.

Accepted layout values are `nil`, `false`, a layout name, or a callable invoked as `call(controller:)`.

Bundler resolves the dummy app against the pinned GitHub release tags. Trashable `v0.14.0` allows Recording Studio `v6.7.1`. The dummy initializer sets `config.authorize_write` because Recording Studio 6.5 writes fail closed without it. The dummy schema includes Trashable `purge_at`.

Gem pages set `content_for :title` and `:subtitle`, `flat_pack_page_nav` for back and close, and `register_page_nav` for page actions. The layout draws the shell. Modal and Turbo-frame responses still pass `layout: false`.

Library grid cards use `card.media(aspect_ratio: "4/3")`. The attachment page uses `card.media(aspect_ratio: "1/1")`. Broken previews, non-image files, and the empty library render `FlatPack::EmptyState`. The description field is `FlatPack::TextArea`.
