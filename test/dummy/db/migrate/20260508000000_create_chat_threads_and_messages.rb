class CreateChatThreadsAndMessages < ActiveRecord::Migration[8.1]
  def change
    create_table :chat_threads, id: :uuid do |t|
      t.string :title, null: false
      t.timestamps
    end

    create_table :chat_messages, id: :uuid do |t|
      t.references :chat_thread, null: false, type: :uuid, foreign_key: true
      t.integer :position, null: false
      t.string :direction, null: false
      t.text :body, null: false
      t.timestamps
    end

    add_index :chat_messages, [:chat_thread_id, :position], unique: true
  end
end