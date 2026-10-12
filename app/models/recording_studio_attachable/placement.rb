# frozen_string_literal: true

module RecordingStudioAttachable
  class Placement < ApplicationRecord
    self.table_name = "recording_studio_attachable_placements"

    if respond_to?(:recording_studio_recordable)
      recording_studio_recordable(
        label: "Image",
        plural_label: "Images",
        root: false
      )
    end

    include RecordingStudio::Capabilities::Trashable.to if defined?(RecordingStudio::Capabilities::Trashable)

    validates :attachment_recording_id, presence: true

    def title
      "Image"
    end
  end
end
