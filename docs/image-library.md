# Image library

A workspace keeps reusable photos in one library. Other gems place those photos on their own pages without copying the file.

## Why a library recordable

Attachable already warns against enabling itself on a shared root. A dedicated `RecordingStudioAttachable::Library` under the root is the sanctioned child:

- The root stays a billing and access bucket.
- Library photos do not mix with other attachments on the workspace.
- Access follows the root through Accessible. People who can see the workspace can see the library.
- Attachable's existing listing, upload, picker, and edit screens work on the library as-is.

Do not enable Attachable on the shared root to fake a library.

## Models

| Type | Role |
| --- | --- |
| `RecordingStudioAttachable::Library` | One per root. Holds `Attachment` children. Find-or-create on first use. |
| `RecordingStudioAttachable::Attachment` | The photo and its caption, credit, and alt text. |
| `RecordingStudioAttachable::Placement` | A pointer from a host page to a library photo, plus Orderable position. |

Caption, credit, and alt live on the photo. A placement does not override them.

## Enable it

On the root:

```ruby
class Workspace < ApplicationRecord
  recording_studio_recordable label: "Workspace", root: true

  include RecordingStudio::Capabilities::ImageLibrary.to
end
```

On each host type that should hold photos from the library:

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
library = RecordingStudioAttachable.library_for(root_recording, actor: current_user)
# or
library = root_recording.image_library(actor: current_user)

parent.place_library_image(attachment_recording: photo, actor: current_user)
parent.upload_to_library_and_place(signed_blob_id: blob.signed_id, actor: current_user)
parent.library_placements
parent.reorder_library_placements!(ordered_recording_ids: ids, actor: current_user)
parent.remove_library_placement(placement_recording: placement, actor: current_user)

RecordingStudioAttachable::Placements.resolve(parent)
RecordingStudioAttachable::Placements.usage_for(photo)
```

A photo from another workspace is refused. A photo that is not a child of this workspace's library is refused.

## Screens

Reuse Attachable's listing, upload, picker, and photo edit screens on the library recording.

- Library page: `library_path(root_recording)` find-or-creates the library and opens the existing listing.
- Host page: `recording_placements_path(parent)` adds from the library, uploads and places, reorders, and removes a placement.
- The existing image picker can target the library: `recording_attachment_picker_path(library)`.
- Photo edit still uses `attachments#show`. Caption, credit, and alt are on that form. If the photo is placed, the page warns how many places use it.

Removing a placement never deletes the photo.

## Trash, restore, and purge

Trashing a library photo leaves its placements. Resolve and public render skip a trashed photo. Restore shows it again.

Permanently deleting the photo (`Recording#destroy!`, including Trashable purge) removes every placement. Attachable owns that cleanup.

## Duplicate, access, and public render

Duplicating a host page copies placements, not files. Each copy still points at the same library photo.

Access to the library follows root access. Public pages should resolve placements and render the photo's caption, credit, alt, and delivery URL. They do not need a second access check on the library when the host page is already public.

```ruby
RecordingStudioAttachable::Placements.resolve(section).each do |item|
  image_tag item.attachment.url_for_variant(:med, rails_url: preview_path),
            alt: item.attachment.alt_text.presence || item.attachment.name
end
```

Name places with `config.placement_place_label` when the default title/name is not enough.

## Presskits

Presskits should stop attaching kit photos directly under an Images section. Enable `ImageLibrary` on the workspace, enable `LibraryPlacement` on the Images section, move existing section attachments into the library, and create placements that point at them. That follow-up stays in Presskits.
