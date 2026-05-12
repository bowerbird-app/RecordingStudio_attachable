class ChatThread < ApplicationRecord
  has_many :chat_messages, dependent: :destroy

  validates :title, presence: true

  def latest_message
    chat_messages.sent.order(sent_at: :desc, created_at: :desc, id: :desc).first
  end
end
