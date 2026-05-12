class ChatMessage < ApplicationRecord
  belongs_to :chat_thread
  has_many :chat_message_attachments, dependent: :destroy
  has_many :attachment_recordings, through: :chat_message_attachments, source: :attachment_recording

  scope :drafts, -> { where(status: "draft") }
  scope :sent, -> { where(status: "sent") }
  scope :timeline_order, -> { order(:position, :created_at, :id) }

  validates :body, presence: true, unless: :draft_or_has_attachments?
  validates :direction, inclusion: { in: %w[incoming outgoing] }
  validates :position, presence: true
  validates :status, inclusion: { in: %w[draft sent] }

  def readonly?
    false
  end

  def draft?
    status == "draft"
  end

  def draft_or_has_attachments?
    draft? || chat_message_attachments.any?
  end

  def sent?
    status == "sent"
  end

  def timestamp
    sent_at || created_at
  end
end
