# frozen_string_literal: true

class CreateRecordingStudioLibrarySampleItems < ActiveRecord::Migration[8.1]
  def change
    create_table :recording_studio_library_sample_items, id: :uuid do |t|
      t.string :title, null: false
      t.text :summary
      t.string :accent, default: "coral"
      t.timestamps
    end
  end
end
