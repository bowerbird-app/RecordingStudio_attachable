Next steps:

1. Install Active Storage if the host app does not already use it.
2. Run `rails generate recording_studio_attachable:migrations`.
3. Run `rails db:migrate`.
4. Ensure host-app domain recordables declare their Recording Studio 4 hierarchy with `recording_studio_recordable(...)`.
5. Include `RecordingStudio::Capabilities::Attachable.to(...)` on each parent recordable that should accept child attachments.
6. Do not add host-specific `allowed_parent_types:` to `RecordingStudioAttachable::Attachment`; the addon declares it as a non-root child recordable and derives allowed parents from the `:attachable` capability.
7. Add the engine Stimulus pins and TipTap addon entrypoints if you use importmap.
8. For reusable photo libraries, pin RecordingStudio Library (GitHub branch `cursor/library-gem-v011-9b63` until tag `v0.1.1`), mount it, and enable `ImageLibrary.to` / `LibraryPlacement.to`. See docs/image-library.md.
