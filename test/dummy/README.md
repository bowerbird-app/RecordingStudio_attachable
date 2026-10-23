# Dummy App

This Rails app exists to validate the Recording Studio Attachable engine inside a realistic authenticated shell.

This checkout also boots Google Drive and Dropbox upload providers on one Attachable host.

Use it to verify:

- Recording Studio 4.3 root recording wiring
- `include RecordingStudio::Capabilities::Attachable.to(...)` opt-in behavior
- `/recording_studio_attachable` mounted engine routes
- Recording Studio core default layout plus FlatPack sidebar, login, and Stimulus upload UI
- a fake My Cloud provider that mounts through `register_adapter_routes`, inherits `ProviderController`, and imports through `ImportRemoteFiles`
- Google Drive (`recording_studio_google_drive`) and Dropbox (`recording_studio_dropbox`) upload providers, Oauth at `/recording_studio_oauth`, and importmap pins for each picker launcher
- Drive client id/secret from dummy Rails credentials (`attachable.google_drive` or `google_drive`; Oauth also reads `recording_studio_oauth.outbound.google_drive`). Dropbox from dummy credentials (`attachable.dropbox` or `dropbox`) or `DROPBOX_APP_KEY` / `DROPBOX_APP_SECRET` (also `DROPBOX_CLIENT_ID` / `DROPBOX_CLIENT_SECRET`)
- docs for `url_mode`, `direct_url_host`, and `preprocessed_variants` on the Config, Resizing, and URL modes pages
- a host-added `:poster` image variant (and no explicit `preprocessed_variants`) so the default preprocess set (`small`/`med`/`large` plus host-added names) is what `/url_modes` demos; `:xlarge` stays unprocessed for the Rails-path fallback row
- twenty press kit JPGs under `db/seed_images/`, portrait, square, and landscape, re-imported when Active Storage blobs are missing from the current Disk service
- operations-API attachment metrics via RecordingStudio Metrics (`attachments.storage_used`, `uploads_over_time`, `by_kind`, `by_content_type`) authorized with AdminRoot `:view`. MCP `0.17.0` tool names replace the identifier's first dot with a hyphen. `from`, `to`, and `interval` apply only to `uploads_over_time`.

Boot from `test/dummy`:

```bash
bundle install
bin/rails db:setup
bin/dev
```

Sign in at `/users/sign_in` with `admin@admin.com` / `Password`. Dummy `User` is a mutable Devise actor, not a recordable; seeds grant Accessible admin on the workspace root. Seeds print the workspace and page upload paths (`/recording_studio_attachable/recordings/<id>/attachments/upload`). The home page also links those paths. The recording id is the workspace root id (home) or the page recording id (page upload).
