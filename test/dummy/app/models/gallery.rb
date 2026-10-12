class Gallery < ApplicationRecord
  recording_studio_recordable(
    label: "Gallery",
    plural_label: "Galleries",
    root: false,
    allowed_parent_types: ["Workspace"]
  )

  include RecordingStudio::Capabilities::LibraryPlacement.to(
    types: ["RecordingStudioAttachable::Attachment"],
    libraries: [:default, :campaign]
  )

  if defined?(RecordingStudio::Capabilities::Orderable)
    include RecordingStudio::Capabilities::Orderable.to(
      allows: ["RecordingStudioLibrary::Placement"]
    )
  end

  validates :title, presence: true

  def readonly?
    false
  end
end
