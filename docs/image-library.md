# Image libraries

A workspace can keep reusable photos in one or more named libraries. Other gems place those photos on their own pages without copying the file.

## Why a library recordable

Attachable already warns against enabling itself on a shared root. A dedicated `RecordingStudioAttachable::Library` under a parent is the sanctioned child:

- The root stays a billing and access bucket.
- Library photos do not mix with other attachments on the workspace.
- A parent can hold many named libraries. Hosts can also enable the library capability on a brand, client, or project so libraries live deeper in the tree.
- Access follows the tree through Accessible.
- Attachable's existing listing, upload, picker, and edit screens work on each library as-is.

Do not enable Attachable on the shared root to fake a library.

## Models

| Type | Role |
| --- | --- |
| `RecordingStudioAttachable::Library` | A named library under a parent. Holds `Attachment` children. |
| `RecordingStudioAttachable::Attachment` | The photo and its caption, credit, and alt text. |
| `RecordingStudioAttachable::Placement` | A pointer from a host page to a library photo, plus Orderable position. |

Caption, credit, and alt live on the photo. A placement does not override them.

`library_for(parent)` / `default_library(parent)` still find-or-create one default library per parent so simple hosts do not have to manage names. Extra libraries are created with a name.

## Enable it

On the root, or on a brand / client / project that should hold libraries:

```ruby
class Workspace < ApplicationRecord
  recording_studio_recordable label: "Workspace", root: true

  include RecordingStudio::Capabilities::ImageLibrary.to
end

class Brand < ApplicationRecord
  recording_studio_recordable label: "Brand", root: false, allowed_parent_types: ["Workspace"]

  include RecordingStudio::Capabilities::ImageLibrary.to
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

  include RecordingStudio::Capabilities::LibraryPlacement.to
  include RecordingStudio::Capabilities::Orderable.to(
    allows: ["RecordingStudioAttachable::Placement"]
  )
end
```

Register the addon types in `config.recordable_types`:

```ruby
"RecordingStudioAttachable::Library"
"RecordingStudioAttachable::Placement"
```

Run `rails generate recording_studio_attachable:migrations` and migrate. Orderable needs its own install if the host reorders placements.

## Helpers

```ruby
library = RecordingStudioAttachable.library_for(parent_recording, actor: current_user)
library = RecordingStudioAttachable.default_library(parent_recording, actor: current_user)
# or
library = parent_recording.image_library(actor: current_user)
library = parent_recording.default_library(actor: current_user)

RecordingStudioAttachable.libraries_for(parent_recording)
RecordingStudioAttachable.libraries_in_root(parent_recording)
parent_recording.image_libraries

library = RecordingStudioAttachable.create_library(parent_recording, name: "Campaign stills", description: "Ads", actor: current_user)
RecordingStudioAttachable.rename_library(library, name: "Campaign", actor: current_user)
RecordingStudioAttachable.trash_library(library, actor: current_user)

parent.place_library_image(attachment_recording: photo, actor: current_user)
parent.upload_to_library_and_place(signed_blob_id: blob.signed_id, library_recording: library, actor: current_user)
parent.library_placements
parent.reorder_library_placements!(ordered_recording_ids: ids, actor: current_user)
parent.remove_library_placement(placement_recording: placement, actor: current_user)

RecordingStudioAttachable::Placements.resolve(parent)
RecordingStudioAttachable::Placements.usage_for(photo)
RecordingStudioAttachable::Placements.usage_for_library(library)
```

A photo from another workspace is refused. A photo that is not in a live library in this workspace is refused. A page may place a photo from any library in the same workspace.

## Screens

Reuse Attachable's listing, upload, picker, and photo edit screens on each library recording.

- Libraries index: `recording_libraries_path(parent)` lists, creates, and renames libraries.
- One library: `library_path(library)` or `library_path(parent)` (the parent shortcut find-or-creates the default library) and opens the existing listing.
- Host page: `recording_placements_path(parent)` adds from a library, uploads and places, reorders, and removes a placement. The picker includes a library switcher when more than one library is offered.
- The existing image picker can target a library: `recording_attachment_picker_path(library)`.
- Photo edit still uses `attachments#show`. Caption, credit, and alt are on that form. If the photo is placed, the page warns how many places use it.

Hosts can restrict which libraries the picker offers:

```ruby
RecordingStudioAttachable.configure do |config|
  config.placement_picker_libraries = ->(parent_recording) {
    RecordingStudioAttachable.libraries_for(parent_recording.root_recording)
  }
end
```

The default offers every live library in the same workspace. The switcher opens on the default library.

Removing a placement never deletes the photo.

## Trash, restore, and purge

Trashing a library photo leaves its placements. Resolve and public render skip a trashed photo. Restore shows it again.

Trashing a library with in-use photos shows the same in-use warning, with counts rolled up across the library. The library and its photos hide until restored.

Permanently deleting a photo (`Recording#destroy!`, including Trashable purge) removes every placement of that photo. Permanently deleting a library removes placements for every photo in it. Attachable owns that cleanup.

## Duplicate, access, and public render

Duplicating a host page copies placements, not files. Each copy still points at the same library photo.

Access to a library follows the tree. People who can see the parent can see its libraries. Public pages should resolve placements and render the photo's caption, credit, alt, and delivery URL. They do not need a second access check on the library when the host page is already public.

```ruby
RecordingStudioAttachable::Placements.resolve(section).each do |item|
  image_tag item.attachment.url_for_variant(:med, rails_url: preview_path),
            alt: item.attachment.alt_text.presence || item.attachment.name
end
```

Name places with `config.placement_place_label` when the default title/name is not enough.

## Presskits

Presskits should stop attaching kit photos directly under an Images section. Enable `ImageLibrary` on the workspace (or on a brand / client if kits live there), enable `LibraryPlacement` on the Images section, move existing section attachments into a library, and create placements that point at them. A workspace may keep a default library plus named ones (for example product vs campaign). The Images picker can switch libraries; restrict `placement_picker_libraries` if a kit should only see one. That follow-up stays in Presskits.
