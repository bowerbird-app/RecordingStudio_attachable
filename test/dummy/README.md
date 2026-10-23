# Dummy App

This Rails app exists to validate the Recording Studio Attachable engine inside a realistic authenticated shell.

Use it to verify:

- Recording Studio 4.3 root recording wiring
- `include RecordingStudio::Capabilities::Attachable.to(...)` opt-in behavior
- `/recording_studio_attachable` mounted engine routes
- Recording Studio core default layout plus FlatPack sidebar, login, and Stimulus upload UI
- a fake My Cloud provider that mounts through `register_adapter_routes`, inherits `ProviderController`, and imports through `ImportRemoteFiles`
- docs for `url_mode`, `direct_url_host`, and `preprocessed_variants` on the Config, Resizing, and URL modes pages
- a host-added `:poster` image variant (and no explicit `preprocessed_variants`) so the default preprocess set (`small`/`med`/`large` plus host-added names) is what `/url_modes` demos; `:xlarge` stays unprocessed for the Rails-path fallback row
- twenty press kit JPGs under `db/seed_images/`, portrait, square, and landscape, re-imported when Active Storage blobs are missing from the current Disk service
- operations-API attachment metrics via RecordingStudio Metrics (`attachments.storage_used`, `uploads_over_time`, `by_kind`, `by_content_type`) authorized with AdminRoot `:view`. MCP `0.17.0` tool names replace the identifier's first dot with a hyphen. `from`, `to`, and `interval` apply only to `uploads_over_time`.
