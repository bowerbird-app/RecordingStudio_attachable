# frozen_string_literal: true

module RecordingStudioAttachable
  class Library < ApplicationRecord
    self.table_name = "recording_studio_attachable_libraries"

    if respond_to?(:recording_studio_recordable)
      recording_studio_recordable(
        label: "Image library",
        plural_label: "Image libraries",
        root: false
      )
    end

    if defined?(RecordingStudio::Capabilities::Attachable)
      include RecordingStudio::Capabilities::Attachable.to(
        allowed_content_types: ["image/*"],
        enabled_attachment_kinds: %i[image]
      )
    end

    include RecordingStudio::Capabilities::Trashable.to if defined?(RecordingStudio::Capabilities::Trashable)

    validates :name, presence: true

    def title
      name.to_s.strip.presence || "Library"
    end
  end
end
