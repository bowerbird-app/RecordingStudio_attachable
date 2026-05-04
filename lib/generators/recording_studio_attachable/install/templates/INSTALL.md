1. Mount the engine and review `config/initializers/recording_studio_attachable.rb`.
2. Ensure Active Storage is installed and direct uploads are wired in your host app.
3. Ensure Recording Studio and RecordingStudio Accessible are installed before using the default authorization flow.
4. Run `rails generate recording_studio_attachable:migrations` and then `rails db:migrate`.
5. Register `RecordingStudioAttachable::Attachment` in `RecordingStudio.configure`.
6. Opt each parent recordable into `RecordingStudio::Capabilities::Attachable.to(...)` and set any per-recordable overrides there.
7. Confirm your host app includes:
   - the `@rails/activestorage` importmap pin
   - `ActiveStorage.start()` in `app/javascript/application.js`
   - eager loading for `controllers/recording_studio_attachable`
8. Validate the mounted engine flow end-to-end:
   - open the attachment listing
   - upload one or more files
   - confirm server-side file type, file size, and file count rules
   - revise metadata and replace a file from the detail page
9. For contributor validation, mirror CI:
   - run `bundle install` inside `test/dummy`
   - run `bundle exec rake db:migrate RAILS_ENV=test` inside `test/dummy`
   - return to the repo root and run `bundle exec rubocop` and `bundle exec rake test`
