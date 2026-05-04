Next steps:

1. Install Active Storage if the host app does not already use it.
2. Run `rails generate recording_studio_attachable:migrations`.
3. Run `rails db:migrate`.
4. Add `RecordingStudioAttachable::Attachment` to `RecordingStudio.configure`.
5. Include `RecordingStudio::Capabilities::Attachable.to(...)` on each parent recordable that should accept child attachments.
6. Add the engine Stimulus pins if you use importmap.
