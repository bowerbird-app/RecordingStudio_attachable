# Recording Studio Attachable

Optional Recording Studio addon gem for uploading and managing images/files as child recordings beneath a recording.

## Highlights

- `RecordingStudio::Capabilities::Attachable.to(...)` opt-in API for parent recordables
- addon-owned `RecordingStudioAttachable::Attachment` recordable with `has_one_attached :file`
- child recording identity with append-only recordable revisions
- FlatPack-based listing and upload UI slice
- Stimulus + Active Storage direct upload flow
- Accessible-backed authorization and Trashable-aware removal when available

## Quick start

1. Add the gem to your host app.
2. Ensure Active Storage and RecordingStudio Accessible are installed.
3. Run `rails generate recording_studio_attachable:install`.
4. Run `rails generate recording_studio_attachable:migrations`.
5. Run `rails db:migrate`.
6. Register `RecordingStudioAttachable::Attachment` in `RecordingStudio.configure`.
7. Opt parent recordables into `RecordingStudio::Capabilities::Attachable.to(...)`.

## Development

The dummy app in `test/dummy` mounts both Recording Studio and this engine so you can validate upload/listing flows inside a realistic shell.
