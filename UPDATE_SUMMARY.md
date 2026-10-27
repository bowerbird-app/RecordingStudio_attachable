# Recording Studio Attachable

Current development pins:

- `recording_studio` git tag `v6.1.0` (`>= 6.1.0`)
- `flat_pack` commit `1fcbafe94f8eb118f0a22182f63f5110fcc97a56` (`FlatPack::VERSION` `0.1.319`, gemspec `>= 0.1.315`)
- `view_component` `4.19.0`
- `recording_studio_metrics` `>= 0.3.0, < 1.0` (root Gemfile tag `v0.5.0`)

`RecordingStudioAttachable.configuration.layout` defaults to `nil`. The engine base controller calls `recording_studio_layout` with that setting. `nil` uses `RecordingStudio.configuration.layout`, then `"recording_studio/default_layout"`.

Accepted layout values are `nil`, `false`, a layout name, or a callable invoked as `call(controller:)`.

Sibling gems that still require `recording_studio` below 6 are widened by `test/support/widen_recording_studio_requirement.rb`, which both Gemfiles load before Bundler evaluates gemspecs. The dummy app pins Trashable `v0.12.0`, which already allows Recording Studio 6.1.0.

Gem pages set `content_for :title` and `:subtitle`, `flat_pack_page_nav` for back and close, and `register_page_nav` for page actions. The layout draws the shell. Modal and Turbo-frame responses still pass `layout: false`.
