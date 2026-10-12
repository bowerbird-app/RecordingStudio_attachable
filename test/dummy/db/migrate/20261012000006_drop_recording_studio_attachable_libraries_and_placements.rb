# frozen_string_literal: true

class DropRecordingStudioAttachableLibrariesAndPlacements < ActiveRecord::Migration[8.1]
  def change
    drop_table :recording_studio_attachable_placements, if_exists: true
    drop_table :recording_studio_attachable_libraries, if_exists: true
  end
end
