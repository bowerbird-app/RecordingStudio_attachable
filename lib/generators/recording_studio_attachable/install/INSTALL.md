Next steps:

1. Install Active Storage if the host app does not already use it.
2. Run `rails generate recording_studio_attachable:migrations`.
3. Run `rails db:migrate`.
4. Ensure Recording Studio 3.0.0+ is installed and each host-app recordable declares its hierarchy with `recording_studio_recordable`.
5. Include `RecordingStudio::Capabilities::Attachable.to(...)` on each parent recordable that should accept child attachments.
6. Do not add host-specific `allowed_parent_types:` to `RecordingStudioAttachable::Attachment`; the addon declares it as a capability-owned child recordable.
7. Add the engine Stimulus pins and TipTap addon entrypoints if you use importmap.
