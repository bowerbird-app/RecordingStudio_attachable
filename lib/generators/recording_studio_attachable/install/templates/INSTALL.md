1. Mount the engine and review `config/initializers/recording_studio_attachable.rb`.
2. Ensure Active Storage is installed and direct uploads are wired in your host app.
3. Ensure Recording Studio 6.1.0+ and RecordingStudio Accessible are installed before using the default authorization flow.
4. Run `rails generate recording_studio_attachable:migrations` and then `rails db:migrate`.
5. Declare each host-app domain recordable with `recording_studio_recordable(...)`, including `root:` and `allowed_parent_types:` for non-root domain recordables.
6. Opt each parent recordable into `RecordingStudio::Capabilities::Attachable.to(...)` and set any per-recordable overrides there.
7. Do not add host-specific `allowed_parent_types:` to `RecordingStudioAttachable::Attachment`; the addon declares it as a non-root child and registers it through the `:attachable` capability.
8. Choose the gem layout in `config/initializers/recording_studio_attachable.rb`:
   - leave `config.layout` unset to follow `RecordingStudio.configuration.layout`, then `"recording_studio/default_layout"`
   - set `config.layout` to a layout name, `false`, or a callable that takes `controller:`
9. Confirm your host app includes:
   - the `@rails/activestorage` importmap pin
   - `ActiveStorage.start()` in `app/javascript/application.js`
   - eager loading for `controllers/recording_studio_attachable`
10. Validate the mounted engine flow end-to-end:
   - open the attachment listing
   - upload one or more files
   - confirm server-side file type, file size, and file count rules
   - revise metadata and replace a file from the detail page
11. For operations-API storage and upload metrics, add RecordingStudio Metrics
    (`>= 0.3.0, < 0.6`, GitHub tag `v0.5.0`). This gem registers `:attachments`
    metrics only. The host calls `RecordingStudioMetrics::Api.register!(api: :operations)`.
    RecordingStudio MCP `0.17.0` then advertises `attachments-storage_used`,
    `attachments-uploads_over_time`, `attachments-by_kind`, and
    `attachments-by_content_type`. Only `attachments.uploads_over_time` takes
    `from`, `to`, and `interval`.
12. For contributor validation, mirror CI:
   - run `bundle install` inside `test/dummy`
   - run `bundle exec rake db:migrate RAILS_ENV=test` inside `test/dummy`
   - return to the repo root and run `bundle exec rubocop` and `bundle exec rake test`
