# frozen_string_literal: true

class CreateRecordingStudioAttachableLibraries < ActiveRecord::Migration[8.1]
  def change
    create_table :recording_studio_attachable_libraries, id: :uuid do |t|
      t.string :name, null: false, default: "Library"
      t.text :description
      t.boolean :default, null: false, default: false
      t.datetime :created_at, null: false
    end
  end
end
