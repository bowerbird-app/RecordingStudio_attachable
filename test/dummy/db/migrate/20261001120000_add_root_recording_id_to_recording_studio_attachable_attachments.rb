# frozen_string_literal: true

class AddRootRecordingIdToRecordingStudioAttachableAttachments < ActiveRecord::Migration[8.1]
  INDEX_NAME = "index_rs_attachable_attachments_on_root_recording_id"
  BACKFILL_SQL = <<~SQL.squish.freeze
    UPDATE recording_studio_attachable_attachments AS attachments
    SET root_recording_id = sources.root_recording_id
    FROM (
      SELECT DISTINCT ON (attachment_id) attachment_id, root_recording_id
      FROM (
        %<recording_sources>s
        %<event_sources>s
      ) candidates
      ORDER BY attachment_id, source_rank
    ) sources
    WHERE attachments.id = sources.attachment_id
      AND attachments.root_recording_id IS NULL
  SQL
  EVENT_RECORDABLE_SOURCE = <<~SQL.squish.freeze
    SELECT events.recordable_id AS attachment_id,
           recordings.root_recording_id,
           2 AS source_rank
    FROM recording_studio_events events
    INNER JOIN recording_studio_recordings recordings
      ON recordings.id = events.recording_id
    WHERE events.recordable_type = 'RecordingStudioAttachable::Attachment'
      AND events.recordable_id IS NOT NULL
      AND recordings.root_recording_id IS NOT NULL
  SQL
  RECORDING_SOURCE = <<~SQL.squish.freeze
    SELECT recordings.recordable_id AS attachment_id,
           recordings.root_recording_id,
           1 AS source_rank
    FROM recording_studio_recordings recordings
    WHERE recordings.recordable_type = 'RecordingStudioAttachable::Attachment'
      AND recordings.recordable_id IS NOT NULL
      AND recordings.root_recording_id IS NOT NULL
  SQL
  EVENT_PREVIOUS_SOURCE = <<~SQL.squish.freeze
    SELECT events.previous_recordable_id AS attachment_id,
           recordings.root_recording_id,
           3 AS source_rank
    FROM recording_studio_events events
    INNER JOIN recording_studio_recordings recordings
      ON recordings.id = events.recording_id
    WHERE events.previous_recordable_type = 'RecordingStudioAttachable::Attachment'
      AND events.previous_recordable_id IS NOT NULL
      AND recordings.root_recording_id IS NOT NULL
  SQL

  def up
    unless column_exists?(:recording_studio_attachable_attachments, :root_recording_id)
      add_column :recording_studio_attachable_attachments, :root_recording_id, :uuid
    end

    unless index_exists?(:recording_studio_attachable_attachments, :root_recording_id, name: INDEX_NAME)
      add_index :recording_studio_attachable_attachments, :root_recording_id, name: INDEX_NAME
    end

    backfill_root_recording_ids
  end

  def down
    if index_exists?(:recording_studio_attachable_attachments, :root_recording_id, name: INDEX_NAME)
      remove_index :recording_studio_attachable_attachments, name: INDEX_NAME
    end

    return unless column_exists?(:recording_studio_attachable_attachments, :root_recording_id)

    remove_column :recording_studio_attachable_attachments, :root_recording_id
  end

  def backfill_root_recording_ids
    return unless backfill_ready?

    execute format(BACKFILL_SQL, recording_sources: recording_sources, event_sources: event_sources)
  end

  private

  def recording_sources
    RECORDING_SOURCE
  end

  def event_sources
    return "" unless table_exists?(:recording_studio_events)

    "UNION ALL #{EVENT_RECORDABLE_SOURCE} UNION ALL #{EVENT_PREVIOUS_SOURCE}"
  end

  def backfill_ready?
    table_exists?(:recording_studio_attachable_attachments) &&
      column_exists?(:recording_studio_attachable_attachments, :root_recording_id) &&
      table_exists?(:recording_studio_recordings)
  end
end
