# Image libraries

A host mounts reusable photo libraries. People upload and edit photos in a library the host already provisioned. They do not create, title, rename, or browse libraries.

Attachable does not own libraries or placements. RecordingStudio Library does. Attachable registers an adapter for `Attachment`, keeps the public helper names as thin wrappers, and keeps the upload page plus the image editor.

## Why a library recordable

Attachable already warns against enabling itself on a shared root. A dedicated `RecordingStudioLibrary::Library` under a parent is the sanctioned child:

- The root stays a billing and access bucket.
- Library photos do not mix with other attachments on the workspace.
- The host enables `ImageLibrary.to` (a thin alias over `Library.to`) on a root, brand, client, or project and gets one library per parent by default.
- Extra libraries in the same parent are keyed (`library_for(parent, key: :campaign)`).
- Access follows the tree through Accessible.
- Writes into a library go through Library's `RecordLibraryItem` / `place_new!`, so allow-lists and upload rights are enforced.

Do not enable Attachable on the shared root to fake a library.

## Models

| Type | Role |
| --- | --- |
| `RecordingStudioLibrary::Library` | A keyed library under a parent. Holds `Attachment` children. The key is the identifier. The label comes from i18n or `config.library_label`, not a user-editable name. |
| `RecordingStudioAttachable::Attachment` | The photo or file, plus caption, credit, and alt text. |
| `RecordingStudioLibrary::Placement` | A pointer from a host page to a library item, plus Orderable position. |

Caption, credit, and alt live on the photo. A placement does not override them.

`RecordingStudioAttachable.library_for(parent)` find-or-creates the default library for that parent (`key: "default"`). A second library is `library_for(parent, key: :campaign)` — idempotent per parent and key. Hosts must call `library_for` before a library page or picker can find the library.

`ImageLibrary.to` and `LibraryPlacement.to` stay as aliases so hosts that already use those names do not have to switch.

## Enable it

Pin Library by GitHub tag, install its migrations, and mount its engine.

```ruby
# Gemfile
gem "recording_studio_library", github: "bowerbird-app/RecordingStudio_library", tag: "v0.1.0"
```

```ruby
mount RecordingStudioLibrary::Engine, at: "/recording_studio_library"
```

On the root, or on a brand / client / project that should hold libraries:

```ruby
class Workspace < ApplicationRecord
  recording_studio_recordable label: "Workspace", root: true

  include RecordingStudio::Capabilities::ImageLibrary.to(
    types: ["RecordingStudioAttachable::Attachment"],
    keys: [:default, :campaign]
  )
end
```

On each host type that should hold photos from a library:

```ruby
class ImagesSection < ApplicationRecord
  recording_studio_recordable(
    label: "Images",
    root: false,
    allowed_parent_types: ["PressKit"]
  )

  include RecordingStudio::Capabilities::LibraryPlacement.to(
    types: ["RecordingStudioAttachable::Attachment"],
    libraries: [:default, :campaign]
  )
  include RecordingStudio::Capabilities::Orderable.to(
    allows: ["RecordingStudioLibrary::Placement"]
  )
end
```

Register the library types in `config.recordable_types`:

```ruby
"RecordingStudioLibrary::Library"
"RecordingStudioLibrary::Placement"
"RecordingStudioAttachable::Attachment"
```

Run Library's install/migrations and Attachable's migrations. Attachable's latest migration drops the old `recording_studio_attachable_libraries` and `recording_studio_attachable_placements` tables. Presskits is unreleased, so no data migration is required.

## Public helpers

These names stay stable and delegate to Library:

```ruby
RecordingStudioAttachable.library_for(parent, key: :default, actor: current_user)
RecordingStudioAttachable.place_library_image(holder, attachment_recording: photo, actor: current_user)
RecordingStudioAttachable.upload_to_library_and_place(parent_recording: holder, signed_blob_id:, library_recording:, actor:)
RecordingStudioAttachable.library_placements(holder, actor: current_user)
RecordingStudioAttachable.reorder_library_placements!(holder, ordered_recording_ids:, actor:)
RecordingStudioAttachable.remove_library_placement(holder, placement_recording:, actor:)
RecordingStudioAttachable::Placements.resolve(holder, actor: current_user)
library_path_for(library)
recording_library_path(parent, key: :campaign)

config.placement_picker_libraries
config.library_label
```

`Placements.resolve` wraps Library's resolved entries and still exposes `attachment_recording` / `attachment`. Resolve uses Library's Accessible-checked path. Anonymous visitors go through Accessible. There is no nil-actor bypass.

`upload_to_library_and_place` uses Library's transactional `place_new!`. If placing fails, the uploaded photo is not left behind.

## Screens

One UI. Library renders the library, picker, and placements editor through the Attachment adapter (thumbnail via an Active Storage variant, title, search text, label/icon). Attachable keeps the screens that are clearly better for images:

- **Library listing / picker / placements** — Library's adapter-rendered screens.
- **Upload** — Attachable's upload page (`recording_attachment_upload_path`). Library's Add button for an Attachment goes there.
- **Image editor** — Attachable's `attachments#show` (caption, credit, alt, variants, trash). Opening a photo from the library listing goes there.

Call `library_for` in the host action, then redirect to Library:

```ruby
library = RecordingStudioAttachable.library_for(root_recording, key: params[:key], actor: Current.actor)
redirect_to recording_studio_library.library_path(library)
```

```ruby
redirect_to recording_studio_library.recording_placements_path(gallery_recording)
```

`library_path_for` still works for host nav. Compatibility routes on Attachable (`recording_library_path`, `recording_placements_path`) redirect to Library.

Labels come from i18n, not a form:

```yaml
en:
  recording_studio_attachable:
    libraries:
      keys:
        default: "Images"
        campaign: "Campaign"
```

Or set `config.library_label` when i18n is not enough. Attachable syncs that, `placement_picker_libraries`, and `placement_place_label` onto Library.

## Trash, restore, and purge

Trash-in-use warning and delete cascade come from Library. Attachable's image editor shows Library's usage list when the photo lives in a library.

Trashing a library photo leaves its placements. Resolve and public render skip a trashed photo. Restore shows it again.

Permanently deleting a photo removes every placement of that photo. Permanently deleting a library removes placements for every item in it.

Removing a placement never deletes the photo.

## Duplicate, access, and public render

Duplicating a host page copies placements, not files. Each copy still points at the same library photo.

Access to a library follows the tree. People who can see the parent can see its libraries. Public pages should resolve placements with an actor (or `nil`, which goes through Accessible) and render the photo's caption, credit, alt, and delivery URL.

```ruby
RecordingStudioAttachable::Placements.resolve(section, actor: current_visitor).each do |item|
  image_tag item.attachment.url_for_variant(:med, rails_url: preview_path),
            alt: item.attachment.alt_text.presence || item.attachment.name
end
```

Name places with `config.placement_place_label` when the default title/name is not enough.

## Presskits

Presskits should keep calling the Attachable helper names. Enable `ImageLibrary` on the workspace (or on a brand / client if kits live there), enable `LibraryPlacement` on the Images section, register Library's types, mount Library, and pass those libraries to `placement_picker_libraries` when a kit should pick from more than one. That follow-up stays in Presskits.
