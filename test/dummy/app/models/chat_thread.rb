class ChatThread < ApplicationRecord
  recording_studio_recordable(
    label: "Chat thread",
    plural_label: "Chat threads",
    root: false,
    allowed_parent_types: ["Workspace"]
  )

  has_many :chat_messages, dependent: :destroy

  validates :title, presence: true

  def latest_message
    chat_messages.sent.order(sent_at: :desc, created_at: :desc, id: :desc).first
  end
end
