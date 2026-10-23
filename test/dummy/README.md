# Dummy App

This Rails app exists to validate the Recording Studio Attachable engine inside a realistic authenticated shell.

Use it to verify:

- Recording Studio 4.3 root recording wiring
- `include RecordingStudio::Capabilities::Attachable.to(...)` opt-in behavior
- `/recording_studio_attachable` mounted engine routes
- Recording Studio core default layout plus FlatPack sidebar, login, and Stimulus upload UI
- built-in optional Google Drive addon wiring on the main dummy upload page
- dummy Google Drive OAuth: by default the outbound `:google_drive` provider uses the local fake login (`/fake_oauth/authorize`, client id `dummy-fake-drive`). Tests always stay on that fake path. To try real Google Drive in development, set these Rails credential keys (values stay in the secret store, not git):

      attachable:
        google_drive:
          client_id:
          client_secret:

  The Google OAuth redirect URI is `<host>/recording_studio_oauth/outbound/callback`. With those keys present, the dummy registers Google's authorize URL (`https://accounts.google.com/o/oauth2/v2/auth`) and token URL (`https://oauth2.googleapis.com/token`), the existing Drive scopes, and offline access with a consent prompt so a refresh token comes back.
- dummy Dropbox OAuth: by default the outbound `:dropbox` provider uses the same local fake login (`/fake_oauth/authorize`, client id `dummy-fake-drive`). Tests always stay on that fake path. To try real Dropbox in development, set these Rails credential keys (values stay in the secret store, not git):

      attachable:
        dropbox:
          client_id:
          client_secret:

  The Dropbox OAuth redirect URI is `<host>/recording_studio_oauth/outbound/callback`. With those keys present, the dummy registers Dropbox's authorize URL (`https://www.dropbox.com/oauth2/authorize`) and token URL (`https://api.dropboxapi.com/oauth2/token`) with `token_access_type=offline`.
- docs for `url_mode`, `direct_url_host`, and `preprocessed_variants` on the Config, Resizing, and URL modes pages
- a host-added `:poster` image variant (and no explicit `preprocessed_variants`) so the default preprocess set (`small`/`med`/`large` plus host-added names) is what `/url_modes` demos; `:xlarge` stays unprocessed for the Rails-path fallback row
- twenty press kit JPGs under `db/seed_images/`, portrait, square, and landscape, re-imported when Active Storage blobs are missing from the current Disk service
- operations-API attachment metrics via RecordingStudio Metrics (`attachments.storage_used`, `uploads_over_time`, `by_kind`, `by_content_type`) authorized with AdminRoot `:view`. MCP `0.17.0` tool names replace the identifier's first dot with a hyphen. `from`, `to`, and `interval` apply only to `uploads_over_time`.
