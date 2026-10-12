# frozen_string_literal: true

require "test_helper"
require Rails.root.join("../../db/migrate/20261012000001_drop_recording_studio_attachable_libraries_and_placements")

class DropAttachableLibrariesMigrationTest < ActiveSupport::TestCase
  setup do
    @connection = ActiveRecord::Base.connection
    @migration = DropRecordingStudioAttachableLibrariesAndPlacements.new
    @migration.verbose = false
    recreate_dropped_tables
  end

  test "up deletes leftover recordings, invitations, and access rows then drops the tables" do
    workspace = Workspace.create!(name: "Drop #{SecureRandom.hex(4)}")
    root = RecordingStudio.root_recording_for(workspace)
    child_recordable = Gallery.create!(title: "Drop child #{SecureRandom.hex(4)}")
    library_id = insert_recording(
      recordable_type: "RecordingStudioAttachable::Library",
      recordable_id: insert_row("recording_studio_attachable_libraries"),
      parent_recording_id: root.id,
      root_recording_id: root.id
    )
    child_id = insert_recording(
      recordable_type: "Gallery",
      recordable_id: child_recordable.id,
      parent_recording_id: library_id,
      root_recording_id: root.id
    )
    placement_id = insert_recording(
      recordable_type: "RecordingStudioAttachable::Placement",
      recordable_id: insert_row("recording_studio_attachable_placements", attachment_recording_id: child_id),
      parent_recording_id: root.id,
      root_recording_id: root.id
    )
    insert_event(library_id)
    insert_event(placement_id)
    insert_retention(library_id)
    invitation_id = insert_invitation(library_id)
    child_access_id, child_access_row_id = insert_access_recording(parent_recording_id: library_id, root_recording_id: root.id)
    dependent_access_id, dependent_access_row_id = insert_access_recording(
      parent_recording_id: root.id,
      root_recording_id: root.id,
      depends_on_recording_id: library_id
    )
    insert_event(child_access_id)

    @migration.up

    refute recording_exists?(library_id)
    refute recording_exists?(placement_id)
    refute event_exists?(library_id)
    refute event_exists?(placement_id)
    refute retention_exists?(library_id)
    refute invitation_exists?(invitation_id)
    refute recording_exists?(child_access_id)
    refute recording_exists?(dependent_access_id)
    refute access_row_exists?(child_access_row_id)
    refute access_row_exists?(dependent_access_row_id)
    refute event_exists?(child_access_id)
    assert_equal root.id, parent_id_for(child_id)
    refute @connection.table_exists?(:recording_studio_attachable_libraries)
    refute @connection.table_exists?(:recording_studio_attachable_placements)
  end

  test "down raises an irreversible migration" do
    error = assert_raises(ActiveRecord::IrreversibleMigration) { @migration.down }
    assert_match(/cannot restore/i, error.message)
  end

  private

  def recreate_dropped_tables
    unless @connection.table_exists?(:recording_studio_attachable_libraries)
      @connection.create_table :recording_studio_attachable_libraries, id: :uuid do |t|
        t.string :key, null: false, default: "default"
        t.datetime :created_at, null: false
      end
    end

    return if @connection.table_exists?(:recording_studio_attachable_placements)

    @connection.create_table :recording_studio_attachable_placements, id: :uuid do |t|
      t.uuid :attachment_recording_id, null: false
      t.datetime :created_at, null: false
    end
  end

  def insert_row(table, **columns)
    id = SecureRandom.uuid
    payload = { id: id, created_at: Time.current }.merge(columns)
    names = payload.keys.map { |key| @connection.quote_column_name(key) }.join(", ")
    values = payload.values.map { |value| @connection.quote(value) }.join(", ")
    @connection.insert("INSERT INTO #{table} (#{names}) VALUES (#{values})")
    id
  end

  def insert_recording(recordable_type:, recordable_id:, parent_recording_id:, root_recording_id:)
    id = SecureRandom.uuid
    now = Time.current
    @connection.insert(<<~SQL.squish)
      INSERT INTO recording_studio_recordings (
        id, recordable_type, recordable_id, parent_recording_id, root_recording_id, created_at, updated_at, trash_root
      ) VALUES (
        #{@connection.quote(id)},
        #{@connection.quote(recordable_type)},
        #{@connection.quote(recordable_id)},
        #{@connection.quote(parent_recording_id)},
        #{@connection.quote(root_recording_id)},
        #{@connection.quote(now)},
        #{@connection.quote(now)},
        FALSE
      )
    SQL
    id
  end

  def insert_event(recording_id)
    id = SecureRandom.uuid
    @connection.insert(<<~SQL.squish)
      INSERT INTO recording_studio_events (
        id, action, recordable_id, recordable_type, recording_id, created_at
      ) VALUES (
        #{@connection.quote(id)},
        'created',
        #{@connection.quote(SecureRandom.uuid)},
        'RecordingStudioAttachable::Library',
        #{@connection.quote(recording_id)},
        #{@connection.quote(Time.current)}
      )
    SQL
  end

  def insert_invitation(recording_id)
    return unless @connection.table_exists?(:recording_studio_access_invitations)

    actor = users_admin
    id = SecureRandom.uuid
    now = Time.current
    @connection.insert(<<~SQL.squish)
      INSERT INTO recording_studio_access_invitations (
        id, recording_id, email, role, token_digest,
        manager_actor_type, manager_actor_id, expires_at, last_sent_at, created_at, updated_at
      ) VALUES (
        #{@connection.quote(id)},
        #{@connection.quote(recording_id)},
        #{@connection.quote("drop-#{SecureRandom.hex(4)}@example.com")},
        'view',
        #{@connection.quote(SecureRandom.hex(32))},
        'User',
        #{@connection.quote(actor.id)},
        #{@connection.quote(now + 1.day)},
        #{@connection.quote(now)},
        #{@connection.quote(now)},
        #{@connection.quote(now)}
      )
    SQL
    id
  end

  def insert_access_recording(parent_recording_id:, root_recording_id:, depends_on_recording_id: nil)
    actor = users_admin
    access_id = insert_row(
      "recording_studio_accesses",
      actor_type: "User",
      actor_id: actor.id,
      role: "view",
      depends_on_recording_id: depends_on_recording_id
    )
    recording_id = insert_recording(
      recordable_type: "RecordingStudio::Access",
      recordable_id: access_id,
      parent_recording_id: parent_recording_id,
      root_recording_id: root_recording_id
    )
    [recording_id, access_id]
  end

  def users_admin
    user = User.find_by(email: "admin@admin.com")
    return user if user.present?

    User.create!(
      email: "admin@admin.com",
      password: "Password",
      password_confirmation: "Password",
      name: "Avery"
    )
  end

  def insert_retention(recording_id)
    return unless @connection.table_exists?(:recording_studio_trashable_retention_settings)

    id = SecureRandom.uuid
    now = Time.current
    @connection.insert(<<~SQL.squish)
      INSERT INTO recording_studio_trashable_retention_settings (
        id, recording_id, created_at, updated_at
      ) VALUES (
        #{@connection.quote(id)},
        #{@connection.quote(recording_id)},
        #{@connection.quote(now)},
        #{@connection.quote(now)}
      )
    SQL
  end

  def recording_exists?(id)
    @connection.select_value("SELECT 1 FROM recording_studio_recordings WHERE id = #{@connection.quote(id)}").present?
  end

  def event_exists?(recording_id)
    @connection.select_value(
      "SELECT 1 FROM recording_studio_events WHERE recording_id = #{@connection.quote(recording_id)}"
    ).present?
  end

  def retention_exists?(recording_id)
    return false unless @connection.table_exists?(:recording_studio_trashable_retention_settings)

    @connection.select_value(
      "SELECT 1 FROM recording_studio_trashable_retention_settings WHERE recording_id = #{@connection.quote(recording_id)}"
    ).present?
  end

  def invitation_exists?(id)
    return false if id.blank?

    @connection.select_value(
      "SELECT 1 FROM recording_studio_access_invitations WHERE id = #{@connection.quote(id)}"
    ).present?
  end

  def access_row_exists?(id)
    return false if id.blank?

    @connection.select_value(
      "SELECT 1 FROM recording_studio_accesses WHERE id = #{@connection.quote(id)}"
    ).present?
  end

  def parent_id_for(id)
    @connection.select_value(
      "SELECT parent_recording_id FROM recording_studio_recordings WHERE id = #{@connection.quote(id)}"
    )
  end
end
