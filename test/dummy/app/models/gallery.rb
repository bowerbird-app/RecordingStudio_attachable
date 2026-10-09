class Gallery < ApplicationRecord
  recording_studio_recordable(
    label: "Gallery",
    plural_label: "Galleries",
    root: false,
    allowed_parent_types: ["Workspace"]
  )

  include RecordingStudio::Capabilities::LibraryPlacement.to

  if defined?(RecordingStudio::Capabilities::Orderable)
    include RecordingStudio::Capabilities::Orderable.to(
      allows: ["RecordingStudioAttachable::Placement"]
    )
  end

  validates :title, presence: true

  def readonly?
    false
  end
end
