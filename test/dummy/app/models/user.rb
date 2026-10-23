class User < ApplicationRecord
  devise :database_authenticatable, :registerable,
         :recoverable, :rememberable, :validatable

  recording_studio_recordable(
    label: "User",
    plural_label: "Users",
    root: false,
    allowed_parent_types: ["Workspace"]
  )
  # Devise updates users (remember token, password).
  skip_callback :update, :before, :raise_immutable_error

  validates :name, presence: true

  def readonly?
    false
  end
end
