# frozen_string_literal: true

class DropRecordingStudioAttachableLibrariesAndPlacements < ActiveRecord::Migration[8.1]
  DROPPED_RECORDABLE_TYPES = [
    "RecordingStudioAttachable::Library",
    "RecordingStudioAttachable::Placement"
  ].freeze
  ACCESS_RECORDABLE = "RecordingStudio::Access"

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
    leftover_sql = leftover_recordings_sql(quoted_types)
    delete_access_pointers(leftover_sql)
    reparent_children(quoted_types)
    delete_events(quoted_types)
    delete_retention(quoted_types)
    delete_recordings(quoted_types)
  end

  def leftover_recordings_sql(quoted_types)
    "SELECT id FROM recording_studio_recordings WHERE recordable_type IN (#{quoted_types})"
  end

  def access_recordings_sql(leftover_sql)
    <<~SQL.squish
      SELECT id FROM recording_studio_recordings
      WHERE recordable_type = #{connection.quote(ACCESS_RECORDABLE)}
        AND (parent_recording_id IN (#{leftover_sql}) #{depends_on_access_sql(leftover_sql)})
    SQL
  end

  def depends_on_access_sql(leftover_sql)
    return "" unless table_exists?(:recording_studio_accesses)
    return "" unless connection.column_exists?(:recording_studio_accesses, :depends_on_recording_id)

    <<~SQL.squish
      OR recordable_id IN (
        SELECT id FROM recording_studio_accesses
        WHERE depends_on_recording_id IN (#{leftover_sql})
      )
    SQL
  end

  def delete_access_pointers(leftover_sql)
    snapshot_access_targets(leftover_sql)
    delete_invitations(leftover_sql)
    delete_pointed_rows(:recording_studio_events, "SELECT id FROM drop_attachable_access_recordings")
    delete_pointed_rows(:recording_studio_trashable_retention_settings, "SELECT id FROM drop_attachable_access_recordings")
    execute("DELETE FROM recording_studio_recordings WHERE id IN (SELECT id FROM drop_attachable_access_recordings)")
    delete_access_rows(leftover_sql)
  end

  def snapshot_access_targets(leftover_sql)
    execute("DROP TABLE IF EXISTS drop_attachable_access_recordings")
    execute("CREATE TEMPORARY TABLE drop_attachable_access_recordings AS #{access_recordings_sql(leftover_sql)}")
    execute("DROP TABLE IF EXISTS drop_attachable_access_rows")
    execute(<<~SQL.squish)
      CREATE TEMPORARY TABLE drop_attachable_access_rows AS
      SELECT recordable_id AS id
      FROM recording_studio_recordings
      WHERE id IN (SELECT id FROM drop_attachable_access_recordings)
    SQL
  end

  def delete_invitations(leftover_sql)
    return unless table_exists?(:recording_studio_access_invitations)

    execute(<<~SQL.squish)
      DELETE FROM recording_studio_access_invitations
      WHERE recording_id IN (#{leftover_sql})
         OR recording_id IN (SELECT id FROM drop_attachable_access_recordings)
    SQL
  end

  def delete_access_rows(leftover_sql)
    return unless table_exists?(:recording_studio_accesses)

    clauses = ["id IN (SELECT id FROM drop_attachable_access_rows)"]
    if connection.column_exists?(:recording_studio_accesses, :depends_on_recording_id)
      clauses << "depends_on_recording_id IN (#{leftover_sql})"
    end

    execute("DELETE FROM recording_studio_accesses WHERE #{clauses.join(' OR ')}")
  end

  def delete_pointed_rows(table, recording_ids_sql)
    return unless table_exists?(table)

    execute("DELETE FROM #{table} WHERE recording_id IN (#{recording_ids_sql})")
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
    delete_pointed_rows(:recording_studio_events, leftover_recordings_sql(quoted_types))
  end

  def delete_retention(quoted_types)
    delete_pointed_rows(:recording_studio_trashable_retention_settings, leftover_recordings_sql(quoted_types))
  end

  def delete_recordings(quoted_types)
    execute(<<~SQL.squish)
      DELETE FROM recording_studio_recordings
      WHERE recordable_type IN (#{quoted_types})
    SQL
  end
end
