Next steps:

1. Install Active Storage if the host app does not already use it.
2. Add `gem "image_processing", "~> 1.2"` and install the configured native processor.
   Ruby integrations such as `ruby-vips` and MiniMagick do not install native libraries:
   - vips: `apt-get install libvips-tools`, `brew install vips`, or `apk add vips`
   - mini_magick: `apt-get install imagemagick`, `brew install imagemagick`, or `apk add imagemagick`
3. Run `rails generate recording_studio_attachable:migrations`.
4. Run `rails db:migrate`.
5. Ensure host-app domain recordables declare their Recording Studio 3 hierarchy with `recording_studio_recordable(...)`.
6. Include `RecordingStudio::Capabilities::Attachable.to(...)` on each parent recordable that should accept child attachments.
7. Do not add host-specific `allowed_parent_types:` to `RecordingStudioAttachable::Attachment`; the addon declares it as a non-root child recordable and derives allowed parents from the `:attachable` capability.
8. Add the engine Stimulus pins and TipTap addon entrypoints if you use importmap.
9. Run `bin/rails recording_studio_attachable:doctor` after installation and during deployment validation.
   Upload success does not prove that preview variants can be processed.
