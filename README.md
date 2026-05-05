# Recording Studio Attachable

Optional Recording Studio addon gem for uploading and managing images/files as child recordings beneath a recording.

## Highlights

- `RecordingStudio::Capabilities::Attachable.to(...)` opt-in API for parent recordables
- addon-owned `RecordingStudioAttachable::Attachment` recordable with `has_one_attached :file`
- child recording identity with append-only recordable revisions
- FlatPack-based listing, search, bulk remove, and upload UI slice
- Stimulus + Active Storage direct upload flow
- Accessible-backed authorization and Trashable-aware removal when available

## Requirements

- Ruby 3.3+
- Rails 8.1+
- Active Storage installed in the host app
- Recording Studio installed in the host app
- RecordingStudio Accessible installed for the default authorization adapter
- RecordingStudio Trashable installed if you want restore support for removed attachments

## Quick start

1. Add the gem to your host app.
2. Ensure Active Storage and RecordingStudio Accessible are installed.
3. Run `rails generate recording_studio_attachable:install`.
4. Run `rails generate recording_studio_attachable:migrations`.
5. Run `rails db:migrate`.
6. Register `RecordingStudioAttachable::Attachment` in `RecordingStudio.configure`.
7. Opt parent recordables into `RecordingStudio::Capabilities::Attachable.to(...)`.

## Host app setup

### 1. Add the gem

```ruby
# Gemfile
gem "recording_studio_attachable"
```

### 2. Register the attachment recordable

```ruby
RecordingStudio.configure do |config|
  config.recordable_types << "RecordingStudioAttachable::Attachment"
end
```

### 3. Opt a parent recordable into attachable

```ruby
class Workspace < ApplicationRecord
  include RecordingStudio::Capabilities::Attachable.to(
    allowed_content_types: ["image/*", "application/pdf", "text/plain"],
    max_file_size: 25.megabytes,
    max_file_count: 20,
    enabled_attachment_kinds: %i[image file]
  )
end
```

### 4. Mount the engine

The install generator adds the mount for you. The default mount path is:

```ruby
mount RecordingStudioAttachable::Engine, at: "/recording_studio_attachable"
```

### 5. Wire direct uploads

The install generator also wires the Active Storage importmap pin, starts Active Storage in `app/javascript/application.js`, and eager-loads the engine Stimulus controllers from `app/javascript/controllers/index.js`.

If your app customizes those entrypoints, make sure all three of these remain true:

- `@rails/activestorage` is pinned in `config/importmap.rb`
- `ActiveStorage.start()` is called in `app/javascript/application.js`
- `controllers/recording_studio_attachable` is eager-loaded from the Stimulus controller index

## Configuration

The generator creates `config/initializers/recording_studio_attachable.rb` with these defaults:

```ruby
RecordingStudioAttachable.configure do |config|
  config.allowed_content_types = ["image/*", "application/pdf"]
  config.max_file_size = 25.megabytes
  config.max_file_count = 20
  config.enabled_attachment_kinds = %i[image file]
  config.default_listing_scope = :direct
  config.default_kind_filter = :all
  config.layout = :blank
  config.auth_roles = {
    view: :view,
    upload: :edit,
    revise: :edit,
    remove: :admin,
    restore: :admin,
    download: :view
  }
end
```

### Per-recordable overrides

Capability options passed to `RecordingStudio::Capabilities::Attachable.to(...)` override the global defaults for that recordable type.

The most important per-recordable options are:

- `allowed_content_types`
- `max_file_size`
- `max_file_count`
- `enabled_attachment_kinds`
- `auth_roles`
- `authorize_with`

### Layouts

Gem views use the bundled blank layout by default:

- centered container
- no top nav
- no sidebar

If you want the gem views to render inside your host app shell instead, set `config.layout` to your app layout name:

```ruby
RecordingStudioAttachable.configure do |config|
  config.layout = "application"
end
```

## Authorization and lifecycle behavior

By default, attachable delegates authorization checks to `RecordingStudioAccessible::Authorization.allowed?` using the configured role map.

Default roles:

- `view`: `:view`
- `upload`: `:edit`
- `revise`: `:edit`
- `remove`: `:admin`
- `restore`: `:admin`
- `download`: `:view`

Removal is Trashable-aware:

- if the child attachment recording responds to Trashable hooks, remove uses trash/restore operations
- otherwise the attachment recording is destroyed outright

## UI expectations

The engine ships with:

- an attachment listing page with scope and kind filters
- name search, pagination, and bulk remove from the attachment listing page
- an upload page with direct uploads, previews, progress, and server-side batch validation
- an attachment detail page for metadata revision and optional file replacement via direct upload

FlatPack is the default UI system for the engine and the dummy app.

## Development

The dummy app in `test/dummy` mounts both Recording Studio and this engine so you can validate upload/listing flows inside a realistic shell.

### Dummy app notes

- the dummy app is a validation shell, not a production template
- CI installs the dummy app bundle and runs dummy-app migrations before the root checks
- make sure engine, Active Storage, and Recording Studio tables are migrated in the dummy app before validating upload flows locally

### CI-aligned validation

Run the same sequence CI uses when you touch dummy-app boot, assets, or migrations:

```bash
cd test/dummy
bundle install
bundle exec rake db:migrate RAILS_ENV=test

cd ../..
bundle exec rubocop
bundle exec rake test
```

### Standard root validation

If your change does not affect the dummy app boot path, the standard root validation command is:

```bash
bundle exec rake test
```
