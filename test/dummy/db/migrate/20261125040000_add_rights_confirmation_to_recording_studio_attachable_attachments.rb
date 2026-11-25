# frozen_string_literal: true

class AddRightsConfirmationToRecordingStudioAttachableAttachments < ActiveRecord::Migration[8.1]
  def change
    add_column :recording_studio_attachable_attachments, :rights_confirmed_at, :datetime
    add_column :recording_studio_attachable_attachments, :rights_confirmed_by, :string
  end
end
