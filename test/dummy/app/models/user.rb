class User < ApplicationRecord
  devise :database_authenticatable, :registerable,
         :recoverable, :rememberable, :validatable

  recording_studio_recordable(
    label: "User",
    plural_label: "Users",
    root: false,
    allowed_parent_types: ["Workspace"]
  )

  include RecordingStudio::Capabilities::Attachable.to(
    max_file_count: 1,
    allowed_content_types: ["image/*"],
    max_file_size: 25.megabytes,
    enabled_attachment_kinds: %i[image]
  )

  validates :name, presence: true

  def readonly?
    false
  end
end
