class User < ApplicationRecord
  devise :database_authenticatable, :registerable,
         :recoverable, :rememberable, :validatable

  recording_studio_recordable(
    label: "User",
    plural_label: "Users",
    root: false,
    allowed_parent_types: ["Workspace"]
  )

  validates :name, presence: true

  def readonly?
    false
  end
end
