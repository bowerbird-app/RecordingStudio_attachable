# frozen_string_literal: true

class DropRecordingStudioAttachableLibrariesAndPlacements < ActiveRecord::Migration[8.1]
  DROPPED_RECORDABLE_TYPES = [
    "RecordingStudioAttachable::Library",
    "RecordingStudioAttachable::Placement"
  ].freeze

  def up
    purge_leftover_recordings
    drop_table :recording_studio_attachable_placements, if_exists: true
    drop_table :recording_studio_attachable_libraries, if_exists: true
  end

  def down
    raise ActiveRecord::IrreversibleMigration,
          "Cannot restore dropped Attachable library and placement tables"
  end

  private

  def purge_leftover_recordings
    return unless table_exists?(:recording_studio_recordings)

    quoted_types = DROPPED_RECORDABLE_TYPES.map { |type| connection.quote(type) }.join(", ")
    reparent_children(quoted_types)
    delete_events(quoted_types)
    delete_retention(quoted_types)
    delete_recordings(quoted_types)
  end

  def reparent_children(quoted_types)
    execute(<<~SQL.squish)
      UPDATE recording_studio_recordings AS children
      SET parent_recording_id = parents.parent_recording_id
      FROM recording_studio_recordings AS parents
      WHERE children.parent_recording_id = parents.id
        AND parents.recordable_type IN (#{quoted_types})
    SQL
  end

  def delete_events(quoted_types)
    return unless table_exists?(:recording_studio_events)

    execute(<<~SQL.squish)
      DELETE FROM recording_studio_events
      WHERE recording_id IN (
        SELECT id FROM recording_studio_recordings
        WHERE recordable_type IN (#{quoted_types})
      )
    SQL
  end

  def delete_retention(quoted_types)
    return unless table_exists?(:recording_studio_trashable_retention_settings)

    execute(<<~SQL.squish)
      DELETE FROM recording_studio_trashable_retention_settings
      WHERE recording_id IN (
        SELECT id FROM recording_studio_recordings
        WHERE recordable_type IN (#{quoted_types})
      )
    SQL
  end

  def delete_recordings(quoted_types)
    execute(<<~SQL.squish)
      DELETE FROM recording_studio_recordings
      WHERE recordable_type IN (#{quoted_types})
    SQL
  end
end
