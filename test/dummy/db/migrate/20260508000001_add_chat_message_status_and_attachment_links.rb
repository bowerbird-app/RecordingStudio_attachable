class AddChatMessageStatusAndAttachmentLinks < ActiveRecord::Migration[8.1]
  def change
    change_column_null :chat_messages, :body, true

    add_column :chat_messages, :status, :string, null: false, default: "draft"
    add_column :chat_messages, :sent_at, :datetime
    add_column :chat_messages, :seeded, :boolean, null: false, default: false

    add_index :chat_messages, :status

    create_table :chat_message_attachments, id: :uuid do |t|
      t.references :chat_message, null: false, type: :uuid, foreign_key: true
      t.references :attachment_recording,
                   null: false,
                   type: :uuid,
                   foreign_key: { to_table: :recording_studio_recordings }

      t.timestamps
    end

    add_index :chat_message_attachments,
              [:chat_message_id, :attachment_recording_id],
              unique: true,
              name: "index_chat_message_attachments_on_message_and_attachment"
  end
end