class Page < ApplicationRecord
  recording_studio_recordable(
    label: "Page",
    plural_label: "Pages",
    root: false,
    allowed_parent_types: ["Workspace"]
  )

  include RecordingStudio::Capabilities::Attachable.to(
    allowed_content_types: [ "image/*" ],
    max_file_size: 25.megabytes,
    max_file_count: 1,
    enabled_attachment_kinds: %i[ image ]
  )

  # The dummy page editor is intentionally mutable even though generic
  # RecordingStudio recordables are immutable snapshots by default.
  before_destroy :raise_page_destroy_immutable_error

  validates :title, presence: true

  def readonly?
    false
  end

  private

  def raise_immutable_error; end

  def raise_page_destroy_immutable_error
    raise ActiveRecord::ReadOnlyRecord, "Recordables are immutable; use revise to create a new snapshot."
  end
end
