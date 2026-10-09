# frozen_string_literal: true

module RecordingStudioAttachable
  class Library < ApplicationRecord
    self.table_name = "recording_studio_attachable_libraries"

    KEY_PATTERN = /\A[a-z][a-z0-9_]*\z/

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

    before_validation :normalize_key
    validates :key, presence: true, format: { with: KEY_PATTERN }

    def title
      RecordingStudioAttachable::Services::LibraryQuery.label_for_key(key)
    end

    private

    def normalize_key
      self.key = RecordingStudioAttachable::Services::LibraryQuery.normalize_key(key)
    rescue ArgumentError
      self.key = key.to_s.strip.downcase
    end
  end
end
