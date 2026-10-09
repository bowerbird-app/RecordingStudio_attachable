# Dummy App

This Rails app exists to validate the Recording Studio Attachable engine inside a realistic authenticated shell.

Use it to verify:

- Recording Studio 4.3 root recording wiring
- `include RecordingStudio::Capabilities::Attachable.to(...)` opt-in behavior
- `/recording_studio_attachable` mounted engine routes
- Recording Studio core default layout plus FlatPack sidebar, login, and Stimulus upload UI
- built-in optional Google Drive addon wiring on the main dummy upload page
- docs for `url_mode`, `direct_url_host`, and `preprocessed_variants` on the Config, Resizing, and URL modes pages
- a host-added `:poster` image variant (and no explicit `preprocessed_variants`) so the default preprocess set (`small`/`med`/`large` plus host-added names) is what `/url_modes` demos; `:xlarge` stays unprocessed for the Rails-path fallback row
- twenty press kit JPGs under `db/seed_images/`, portrait, square, and landscape, re-imported when Active Storage blobs are missing from the current Disk service
- host-mounted image libraries (`/images` and `/campaign`) and a Gallery that places photos from both (`/galleries/:id`) so listing, picker switcher, the shared list/slides/grid editor, add-from-library, upload-and-place, reorder, trash warning, and purge can be walked through
- operations-API attachment metrics via RecordingStudio Metrics (`attachments.storage_used`, `uploads_over_time`, `by_kind`, `by_content_type`) authorized with AdminRoot `:view`
