1. Mount the engine and review `config/initializers/recording_studio_attachable.rb`.
2. Ensure Active Storage is installed and direct uploads are wired in your host app.
3. Ensure Recording Studio 7 (`>= 7.0, < 8.0`) and RecordingStudio Accessible are installed before using the default authorization flow.
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
    (`>= 0.9.0, < 1.0`, GitHub tag `v0.9.0`). This gem registers `:attachments`
    metrics only. The host calls `RecordingStudioMetrics::Api.register!(api: :operations)`.
    RecordingStudio MCP `0.17.0` then advertises `attachments-storage_used`,
    `attachments-uploads_over_time`, `attachments-by_kind`, and
    `attachments-by_content_type`. Only `attachments.uploads_over_time` takes
    `from`, `to`, and `interval`. For the upload, attach, and import writes,
    MCP `0.44` needs `include_tools(*RecordingStudioAttachable::McpCopy.tool_names)`
    on the same named APIs you passed to `Api.register!`.
12. To leave Rails' anonymous `POST /rails/active_storage/direct_uploads` undrawn, rerun the generator with `--restrict-active-storage-routes`, or apply the same edits by hand. The flag is off by default. Existing apps keep Rails' routes.
    - Set `config.active_storage.draw_routes = false`.
    - Set `ActiveStorage.draw_routes = false` in that same class body. Devise reloads routes from `before_eager_load`, and Active Storage copies the config later. The module attribute is what that reload reads. Do not copy it from an initializer `before` edge. That edge reshuffles boot.
    - Call `RecordingStudioAttachable::ActiveStorageRoutes.draw(self)` inside `routes.draw`. That draws the signed blob redirect, the representation redirect, and Disk show and update when the current service in `config/storage.yml` is Disk. Direct uploads and the proxy routes stay undrawn.
    - Keep the Rails signature on the blob redirect and the disk token. You can also require a login. Set `config.active_storage.urls_expire_in` so the signed ids expire. A variation key is a digest of the transform and works on every blob. It is not a secret.
    - `config.warn_on_active_storage_routes` (default true) logs a boot warning when `direct_uploads` is still drawn. Set it to false to silence the log.
    - `PurgeUnattachedBlobsJob` only deletes blobs this gem tagged. Schedule your own purge for old unattached blobs that lack the `recording_studio_attachable` tag.
13. For contributor validation, mirror CI:
   - run `bundle install` inside `test/dummy`
   - run `bundle exec rake db:migrate RAILS_ENV=test` inside `test/dummy`
   - return to the repo root and run `bundle exec rubocop` and `bundle exec rake test`
