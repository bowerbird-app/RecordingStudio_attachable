# frozen_string_literal: true

class CreateRecordingStudioLibraryPlacements < ActiveRecord::Migration[8.1]
  def change
    create_table :recording_studio_library_placements, id: :uuid do |t|
      t.uuid :item_recording_id, null: false
      t.datetime :created_at, null: false

      t.index :item_recording_id
    end
  end
end
