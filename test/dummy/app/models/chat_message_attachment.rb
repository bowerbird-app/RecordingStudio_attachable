class ChatMessageAttachment < ApplicationRecord
  belongs_to :chat_message
  belongs_to :attachment_recording, class_name: "RecordingStudio::Recording"

  validates :attachment_recording_id, uniqueness: { scope: :chat_message_id }
  validate :attachment_recording_must_be_attachable

  private

  def attachment_recording_must_be_attachable
    return if attachment_recording.blank?
    return if attachment_recording.recordable_type == "RecordingStudioAttachable::Attachment"

    errors.add(:attachment_recording, "must be an attachment recording")
  end
end