# frozen_string_literal: true

require "test_helper"
require "fileutils"
require "securerandom"
require "tmpdir"
require_relative "../app/services/recording_studio_attachable/services/application_service"
require_relative "../app/services/recording_studio_attachable/services/record_attachment_upload"
require_relative "../app/services/recording_studio_attachable/services/record_attachment_uploads"
require_relative "../app/services/recording_studio_attachable/services/import_attachment"
require_relative "../app/services/recording_studio_attachable/services/import_attachments"
require_relative "../app/services/recording_studio_attachable/services/replace_attachment_file"
require_relative "../app/services/recording_studio_attachable/services/revise_attachment_metadata"
require_relative "../db/migrate/20250101000003_add_root_recording_id_to_recording_studio_attachable_attachments"

unless defined?(ApplicationRecord)
  class ApplicationRecord < ActiveRecord::Base
    self.abstract_class = true
  end
end

unless defined?(ActiveStorage::Blob)
  module ActiveStorage
    class Blob < ActiveRecord::Base
      self.table_name = "active_storage_blobs"

      def self.find_signed!(*); end

      def self.create_and_upload!(**); end

      def purge
        destroy
      end
    end

    class Attachment < ActiveRecord::Base
      self.table_name = "active_storage_attachments"
      belongs_to :blob, class_name: "ActiveStorage::Blob"
    end
  end

  ActiveStorage::Blob.has_many :attachments, class_name: "ActiveStorage::Attachment", foreign_key: :blob_id
end

unless ApplicationRecord.respond_to?(:has_one_attached)
  ApplicationRecord.define_singleton_method(:has_one_attached) do |*_args|
  end
end

require_relative "../app/models/recording_studio_attachable/attachment"

class StorageLimitTest < Minitest::Test
  DATABASE_URL = ENV.fetch(
    "DATABASE_URL",
    "postgres://postgres:postgres@localhost:5432/recording_studio_attachable_test"
  )

  class BlobDouble
    attr_reader :id, :byte_size, :content_type, :signed_id, :attachments
    attr_accessor :purged

    def initialize(id:, byte_size:, content_type: "image/png", signed_id: nil, attached: false)
      @id = id
      @byte_size = byte_size
      @content_type = content_type
      @signed_id = signed_id || id
      @purged = false
      attached_flag = attached
      @attachments = Object.new
      @attachments.define_singleton_method(:exists?) { attached_flag }
      @attachments.define_singleton_method(:blank?) { false }
    end

    def persisted?
      !id.nil?
    end

    def purge
      self.purged = true
    end

    def filename
      name = "file.png"
      Struct.new(:value) do
        def to_s
          value
        end

        def base
          "file"
        end
      end.new(name)
    end
  end

  class EventRow < ActiveRecord::Base
    self.table_name = "recording_studio_events"
  end

  class RecordingRow < ActiveRecord::Base
    self.table_name = "recording_studio_recordings"
    has_many :events, class_name: "StorageLimitTest::EventRow", foreign_key: :recording_id, dependent: :delete_all
  end

  class PlanHandle
    attr_reader :amounts, :remaining

    def initialize(remaining:, error: nil)
      @remaining = remaining
      @amounts = []
      @error = error
    end

    def with_capacity!(amount)
      @amounts << amount
      raise @error if @error && amount > remaining

      yield
    end
  end

  def setup
    connect!
    @original_configuration = RecordingStudioAttachable.instance_variable_get(:@configuration)
    @configuration = RecordingStudioAttachable::Configuration.new
    RecordingStudioAttachable.instance_variable_set(:@configuration, @configuration)
    @stripe_defined = defined?(RecordingStudioStripe)
    stub_recording_studio!
    RecordingStudioAttachable::StorageLimit.reset!
    @record_calls = 0
    @created_ids = { attachments: [], blobs: [], links: [], recordings: [], events: [] }
  end

  def teardown
    delete_created_rows
    remove_stripe! unless @stripe_defined
    RecordingStudioAttachable.instance_variable_set(:@configuration, @original_configuration)
    RecordingStudioAttachable::StorageLimit.reset!
  end

  def test_max_file_size_rejects_the_same_blob_when_storage_limit_is_off_and_on
    parent = parent_recording
    oversized = BlobDouble.new(id: SecureRandom.uuid, byte_size: 2.megabytes + 1)
    exact = BlobDouble.new(id: SecureRandom.uuid, byte_size: 2.megabytes)

    [false, true].each do |limit_on|
      install_stripe!(remaining: 50.megabytes) if limit_on
      remove_stripe! unless limit_on
      @configuration.storage_limit = limit_on ? :storage_bytes : nil
      oversized.purged = false

      result = upload(parent, oversized, max_file_size: 2.megabytes)

      assert result.failure?, "limit_on=#{limit_on}"
      assert_equal "Blob exceeds maximum file size", result.error
      assert_equal false, oversized.purged
      assert_empty handle_amounts

      success = upload(parent, exact, max_file_size: 2.megabytes)
      assert success.success?, "limit_on=#{limit_on} exact file should upload"
    end
  end

  def test_disabled_or_missing_stripe_uploads_without_calling_stripe
    parent = parent_recording
    blob = BlobDouble.new(id: SecureRandom.uuid, byte_size: 90)
    remove_stripe!
    @configuration.storage_limit = :storage_bytes

    result = upload(parent, blob)

    assert result.success?
    assert_nil defined?(RecordingStudioStripe)

    install_stripe!(remaining: 10)
    @configuration.storage_limit = nil
    second = upload(parent, BlobDouble.new(id: SecureRandom.uuid, byte_size: 90))

    assert second.success?
    assert_empty handle_amounts
  end

  def test_usage_provider_registers_and_a_second_register_replaces_the_proc
    install_stripe!(remaining: 100)
    @configuration.storage_limit = :storage_bytes
    root_id = insert_recording(recordable_type: "Workspace")
    blob_id = insert_blob(byte_size: 42)
    attachment_id = insert_attachment(byte_size: 42, root_recording_id: root_id)
    insert_link(attachment_id, blob_id)
    old_calls = 0
    RecordingStudioStripe.register_limit_usage(:storage_bytes) do
      old_calls += 1
      7
    end

    RecordingStudioAttachable::StorageLimit.register_usage!
    root = Struct.new(:id).new(root_id)
    value = RecordingStudioStripe.configuration.limit_usage_for("storage_bytes").call(root)

    assert_equal 42, value
    assert_equal 0, old_calls
    assert_equal 42, RecordingStudioAttachable.storage_bytes_for(root)
  end

  def test_register_usage_does_not_fetch_limits
    install_stripe!(remaining: 100)
    @configuration.storage_limit = :not_a_real_limit
    fetched = false
    RecordingStudioStripe::Limits.define_singleton_method(:fetch) do |*|
      fetched = true
      raise "fetched"
    end

    RecordingStudioAttachable::StorageLimit.register_usage!

    assert_equal false, fetched
  end

  def test_storage_bytes_for_sums_distinct_blobs_for_the_right_root
    root_id = insert_recording(recordable_type: "Workspace")
    other_root_id = insert_recording(recordable_type: "Workspace")
    shared_id = insert_blob(byte_size: 40)
    only_id = insert_blob(byte_size: 15)
    zero_id = insert_blob(byte_size: 0)
    other_id = insert_blob(byte_size: 7)
    first = insert_attachment(byte_size: 40, root_recording_id: root_id)
    second = insert_attachment(byte_size: 40, root_recording_id: root_id)
    third = insert_attachment(byte_size: 15, root_recording_id: root_id)
    zero = insert_attachment(byte_size: 0, root_recording_id: root_id)
    other = insert_attachment(byte_size: 7, root_recording_id: other_root_id)
    uncounted = insert_attachment(byte_size: 99, root_recording_id: nil)
    insert_link(first, shared_id)
    insert_link(second, shared_id)
    insert_link(third, only_id)
    insert_link(zero, zero_id)
    insert_link(other, shared_id)
    insert_link(uncounted, other_id)
    insert_variant(shared_id)

    assert_equal 55, RecordingStudioAttachable.storage_bytes_for(root_for(root_id))
    assert_equal 40, RecordingStudioAttachable.storage_bytes_for(root_for(other_root_id))
    assert_equal 55, RecordingStudioAttachable.storage_bytes_for(root_for(root_id))
  end

  def test_metadata_revision_replacement_trash_and_destroy_follow_retained_rows
    root_id = insert_recording(recordable_type: "Workspace")
    old_blob = insert_blob(byte_size: 10)
    new_blob = insert_blob(byte_size: 40)
    original = insert_attachment(byte_size: 10, root_recording_id: root_id)
    insert_link(original, old_blob)
    root = root_for(root_id)

    assert_equal 10, RecordingStudioAttachable.storage_bytes_for(root)

    revision = insert_attachment(byte_size: 10, root_recording_id: root_id)
    insert_link(revision, old_blob)
    assert_equal 10, RecordingStudioAttachable.storage_bytes_for(root)

    replacement = insert_attachment(byte_size: 40, root_recording_id: root_id)
    insert_link(replacement, new_blob)
    assert_equal 50, RecordingStudioAttachable.storage_bytes_for(root)

    recording_id = insert_recording(
      recordable_type: "RecordingStudioAttachable::Attachment",
      recordable_id: original,
      root_recording_id: root_id
    )
    connection.execute(
      "UPDATE recording_studio_recordings SET trashed_at = #{connection.quote(Time.now.utc)} WHERE id = #{connection.quote(recording_id)}"
    )
    assert_equal 50, RecordingStudioAttachable.storage_bytes_for(root)

    connection.execute(
      "UPDATE recording_studio_recordings SET trashed_at = NULL WHERE id = #{connection.quote(recording_id)}"
    )
    assert_equal 50, RecordingStudioAttachable.storage_bytes_for(root)

    connection.execute("DELETE FROM recording_studio_recordings WHERE id = #{connection.quote(recording_id)}")
    @created_ids[:recordings].delete(recording_id)

    assert_equal 50, RecordingStudioAttachable.storage_bytes_for(root)
  end

  def test_trash_and_restore_keep_bytes_and_recording_destroy_frees_them
    byte_size = 104_857_600
    root_id = insert_recording(recordable_type: "Workspace")
    blob_id = insert_blob(byte_size: byte_size)
    attachment_id = insert_attachment(byte_size: byte_size, root_recording_id: root_id)
    link_id = insert_link(attachment_id, blob_id)
    recording_id = insert_recording(
      recordable_type: "RecordingStudioAttachable::Attachment",
      recordable_id: attachment_id,
      root_recording_id: root_id,
      parent_recording_id: root_id
    )
    root = root_for(root_id)

    assert_equal byte_size, RecordingStudioAttachable.storage_bytes_for(root)

    recording = attachment_recording_model.find(recording_id)
    recording.update!(trashed_at: Time.current)
    assert_equal byte_size, RecordingStudioAttachable.storage_bytes_for(root)

    recording.update!(trashed_at: nil)
    assert_equal byte_size, RecordingStudioAttachable.storage_bytes_for(root)

    with_test_storage_service { recording.destroy! }
    @created_ids[:recordings].delete(recording_id)
    @created_ids[:links].delete(link_id)
    @created_ids[:blobs].delete(blob_id)

    assert_equal 0, RecordingStudioAttachable.storage_bytes_for(root)
    assert_nil connection.select_value(
      "SELECT id FROM active_storage_attachments WHERE id = #{connection.quote(link_id)}"
    )
    assert_nil connection.select_value(
      "SELECT id FROM active_storage_blobs WHERE id = #{connection.quote(blob_id)}"
    )
  end

  def test_recording_destroy_releases_replaced_snapshots_and_keeps_a_shared_blob
    root_id = insert_recording(recordable_type: "Workspace")
    other_root_id = insert_recording(recordable_type: "Workspace")
    old_blob = insert_blob(byte_size: 10)
    shared_blob = insert_blob(byte_size: 40)
    original = insert_attachment(byte_size: 10, root_recording_id: root_id)
    replacement = insert_attachment(byte_size: 40, root_recording_id: root_id)
    other = insert_attachment(byte_size: 40, root_recording_id: other_root_id)
    old_link = insert_link(original, old_blob)
    shared_link = insert_link(replacement, shared_blob)
    other_link = insert_link(other, shared_blob)
    recording_id = insert_recording(
      recordable_type: "RecordingStudioAttachable::Attachment",
      recordable_id: replacement,
      root_recording_id: root_id,
      parent_recording_id: root_id
    )
    event_id = insert_event(recording_id: recording_id, recordable_id: replacement, previous_recordable_id: original)
    root = root_for(root_id)
    other_root = root_for(other_root_id)

    assert_equal 50, RecordingStudioAttachable.storage_bytes_for(root)
    assert_equal 40, RecordingStudioAttachable.storage_bytes_for(other_root)

    recording = attachment_recording_model.find(recording_id)
    with_test_storage_service { recording.destroy! }
    @created_ids[:recordings].delete(recording_id)
    @created_ids[:events].delete(event_id)
    @created_ids[:links].delete(old_link)
    @created_ids[:links].delete(shared_link)
    @created_ids[:blobs].delete(old_blob)

    assert_equal 0, RecordingStudioAttachable.storage_bytes_for(root)
    assert_equal 40, RecordingStudioAttachable.storage_bytes_for(other_root)
    assert_nil connection.select_value("SELECT id FROM active_storage_blobs WHERE id = #{connection.quote(old_blob)}")
    refute_nil connection.select_value("SELECT id FROM active_storage_blobs WHERE id = #{connection.quote(shared_blob)}")
    assert_nil connection.select_value("SELECT id FROM active_storage_attachments WHERE id = #{connection.quote(shared_link)}")
    refute_nil connection.select_value("SELECT id FROM active_storage_attachments WHERE id = #{connection.quote(other_link)}")
  end

  def test_backfill_stamps_live_recordings_and_event_snapshots_and_leaves_orphans
    root_id = insert_recording(recordable_type: "Workspace")
    live = insert_attachment(byte_size: 8, root_recording_id: nil)
    previous = insert_attachment(byte_size: 9, root_recording_id: nil)
    orphan = insert_attachment(byte_size: 11, root_recording_id: nil)
    recording_id = insert_recording(
      recordable_type: "RecordingStudioAttachable::Attachment",
      recordable_id: live,
      root_recording_id: root_id
    )
    insert_event(recording_id: recording_id, recordable_id: live, previous_recordable_id: previous)

    AddRootRecordingIdToRecordingStudioAttachableAttachments.new.backfill_root_recording_ids

    assert_equal root_id, attachment_root(live)
    assert_equal root_id, attachment_root(previous)
    assert_nil attachment_root(orphan)
  end

  def test_upload_inside_exact_and_above_remaining_capacity
    install_stripe!(remaining: 120)
    @configuration.storage_limit = :storage_bytes
    parent = parent_recording
    inside = BlobDouble.new(id: SecureRandom.uuid, byte_size: 80)

    assert upload(parent, inside).success?
    assert_equal [80], handle_amounts

    exact = BlobDouble.new(id: SecureRandom.uuid, byte_size: 120)
    @handle = PlanHandle.new(remaining: 120)
    assert upload(parent, exact).success?
    assert_equal [120], @handle.amounts

    plan_error = RecordingStudioStripe::PlanLimitReached.new(handle: @handle)
    @handle = PlanHandle.new(remaining: 119, error: plan_error)
    above = BlobDouble.new(id: SecureRandom.uuid, byte_size: 120)
    raised = assert_raises(RecordingStudioStripe::PlanLimitReached) { upload(parent, above) }
    assert_same plan_error, raised
    assert_equal true, above.purged
    assert_equal [120], @handle.amounts
  end

  def test_direct_upload_passes_byte_size_through_incoming_bytes
    install_stripe!(remaining: 500)
    @configuration.storage_limit = :storage_bytes
    blob = BlobDouble.new(id: SecureRandom.uuid, byte_size: 64)
    parent = parent_recording

    assert_raises(RecordingStudioAttachable::StorageLimitError) do
      RecordingStudioAttachable::StorageLimit.with_storage_capacity!(parent.root_recording, blob.byte_size) { flunk "yielded" }
    end

    assert upload(parent, blob).success?
    assert_equal [64], handle_amounts
    assert_equal 64, handle_amounts.first
    assert_instance_of Integer, handle_amounts.first
  end

  def test_batch_checks_the_sum_once_and_a_batch_over_remaining_creates_no_rows
    install_stripe!(remaining: 200)
    @configuration.storage_limit = :storage_bytes
    parent = parent_recording
    first = BlobDouble.new(id: SecureRandom.uuid, byte_size: 60, signed_id: "batch-60")
    second = BlobDouble.new(id: SecureRandom.uuid, byte_size: 50, signed_id: "batch-50")
    before = RecordingStudioAttachable::Attachment.count

    assert upload_batch(parent, [first, second]).success?
    assert_equal [110], handle_amounts
    assert_equal 2, @record_calls

    @record_calls = 0
    @handle = PlanHandle.new(remaining: 100, error: RecordingStudioStripe::PlanLimitReached.new)
    third = BlobDouble.new(id: SecureRandom.uuid, byte_size: 60, signed_id: "over-60")
    fourth = BlobDouble.new(id: SecureRandom.uuid, byte_size: 50, signed_id: "over-50")
    raised = assert_raises(RecordingStudioStripe::PlanLimitReached) { upload_batch(parent, [third, fourth]) }

    assert_instance_of RecordingStudioStripe::PlanLimitReached, raised
    assert_equal [110], @handle.amounts
    assert_equal 0, @record_calls
    assert_equal before, RecordingStudioAttachable::Attachment.count
    assert_equal true, third.purged
    assert_equal true, fourth.purged
  end

  def test_import_path_cannot_bypass_the_storage_claim
    install_stripe!(remaining: 10)
    @configuration.storage_limit = :storage_bytes
    parent = parent_recording
    blob = BlobDouble.new(id: SecureRandom.uuid, byte_size: 25, content_type: "image/png")
    plan_error = RecordingStudioStripe::PlanLimitReached.new
    @handle = PlanHandle.new(remaining: 10, error: plan_error)

    raised = assert_raises(RecordingStudioStripe::PlanLimitReached) do
      import_one(parent, blob)
    end

    assert_same plan_error, raised
    assert_equal [25], @handle.amounts
    assert_equal 0, @record_calls
    assert_equal true, blob.purged
  end

  def test_zero_byte_and_already_retained_blobs_skip_stripe_capacity
    install_stripe!(remaining: 0)
    @handle = PlanHandle.new(remaining: 0, error: RecordingStudioStripe::PlanLimitReached.new)
    @configuration.storage_limit = :storage_bytes
    parent = parent_recording
    zero = BlobDouble.new(id: SecureRandom.uuid, byte_size: 0)

    assert upload(parent, zero).success?
    assert_empty handle_amounts

    retained_id = insert_blob(byte_size: 40)
    attachment_id = insert_attachment(byte_size: 40, root_recording_id: parent.root_recording.id)
    insert_link(attachment_id, retained_id)
    retained = BlobDouble.new(id: retained_id, byte_size: 40)

    assert upload(parent, retained).success?
    assert_empty handle_amounts
    assert_equal 40, RecordingStudioAttachable.storage_bytes_for(parent.root_recording)
  end

  def test_capacity_rejection_purges_only_unattached_blobs
    install_stripe!(remaining: 1)
    @handle = PlanHandle.new(remaining: 1, error: RecordingStudioStripe::PlanLimitReached.new(message: "full"))
    @configuration.storage_limit = :storage_bytes
    parent = parent_recording
    loose = BlobDouble.new(id: SecureRandom.uuid, byte_size: 30, attached: false)
    shared = BlobDouble.new(id: SecureRandom.uuid, byte_size: 30, attached: true)

    assert_raises(RecordingStudioStripe::PlanLimitReached) { upload(parent, loose) }
    assert_raises(RecordingStudioStripe::PlanLimitReached) { upload(parent, shared) }

    assert_equal true, loose.purged
    assert_equal false, shared.purged
  end

  def test_direct_upload_validation_failure_does_not_purge
    install_stripe!(remaining: 500)
    @configuration.storage_limit = :storage_bytes
    parent = parent_recording
    blob = BlobDouble.new(id: SecureRandom.uuid, byte_size: 20, content_type: "text/plain")

    result = upload(parent, blob)

    assert result.failure?
    assert_includes result.error, "is not allowed"
    assert_equal false, blob.purged
    assert_empty handle_amounts
  end

  def test_missing_or_non_quantity_limit_raises_storage_limit_unknown
    install_stripe!(remaining: 500)
    parent = parent_recording
    blob = BlobDouble.new(id: SecureRandom.uuid, byte_size: 20)
    @configuration.storage_limit = :missing_limit

    missing = capture_attachable_error { upload(parent, blob) }
    assert_instance_of RecordingStudioAttachable::StorageLimitUnknown, missing
    assert_includes missing.message, "missing_limit"

    @configuration.storage_limit = :counted_items
    counted = capture_attachable_error { upload(parent, blob) }
    assert_instance_of RecordingStudioAttachable::StorageLimitUnknown, counted
    assert_includes counted.message, "counted_items"
    assert_includes counted.message, "quantity"
  end

  def test_unsaved_blob_raises_storage_limit_error
    install_stripe!(remaining: 500)
    @configuration.storage_limit = :storage_bytes
    parent = parent_recording
    blob = BlobDouble.new(id: nil, byte_size: 20)

    error = capture_attachable_error { upload(parent, blob) }
    assert_instance_of RecordingStudioAttachable::StorageLimitError, error
    assert_includes error.message, "unsaved blob"
  end

  def test_nested_claim_rejects_a_blob_outside_the_reservation
    install_stripe!(remaining: 500)
    @configuration.storage_limit = :storage_bytes
    root = root_for(SecureRandom.uuid)
    billing = billing_for(@handle)
    root.define_singleton_method(:billing) { billing }
    kept = BlobDouble.new(id: SecureRandom.uuid, byte_size: 10)
    extra = BlobDouble.new(id: SecureRandom.uuid, byte_size: 5)
    incoming = RecordingStudioAttachable::StorageLimit::IncomingBytes.for(root, [kept])

    RecordingStudioAttachable::StorageLimit.with_storage_capacity!(root, incoming) do
      assert_raises(RecordingStudioAttachable::StorageLimitError) do
        other = RecordingStudioAttachable::StorageLimit::IncomingBytes.for(root, [extra])
        RecordingStudioAttachable::StorageLimit.with_storage_capacity!(root, other) { flunk "outside blob" }
      end
      covered = RecordingStudioAttachable::StorageLimit::IncomingBytes.for(root, [kept])
      assert_equal :covered, RecordingStudioAttachable::StorageLimit.with_storage_capacity!(root, covered) { :covered }
    end

    assert_equal [10], handle_amounts
  end

  def test_plan_limit_inside_an_open_recording_transaction_purges_after_the_transaction_exits
    install_stripe!(remaining: 1)
    @handle = PlanHandle.new(remaining: 1, error: RecordingStudioStripe::PlanLimitReached.new)
    @configuration.storage_limit = :storage_bytes
    root = root_for(SecureRandom.uuid)
    billing = billing_for(@handle)
    root.define_singleton_method(:billing) { billing }
    blob = BlobDouble.new(id: SecureRandom.uuid, byte_size: 80)
    incoming = RecordingStudioAttachable::StorageLimit::IncomingBytes.for(root, [blob])
    purged_while_open = nil

    assert_raises(RecordingStudioStripe::PlanLimitReached) do
      with_recording_transaction do
        RecordingStudioAttachable::StorageLimit.tracking_discards do
          RecordingStudio::Recording.transaction do
            RecordingStudioAttachable::StorageLimit.with_storage_capacity!(root, incoming) { flunk "yielded" }
          rescue RecordingStudioStripe::PlanLimitReached
            purged_while_open = blob.purged
            raise
          end
        end
      end
    end

    assert_equal false, purged_while_open
    assert_equal true, blob.purged
  end

  def test_replace_claims_only_the_new_blob
    install_stripe!(remaining: 100)
    @configuration.storage_limit = :storage_bytes
    root_id = SecureRandom.uuid
    old_blob = insert_blob(byte_size: 10)
    attachment_id = insert_attachment(byte_size: 10, root_recording_id: root_id)
    insert_link(attachment_id, old_blob)
    replacement = BlobDouble.new(id: SecureRandom.uuid, byte_size: 40, signed_id: "replacement")
    attachment_recording = attachment_recording_for(root_id, attachment_id)

    result = nil
    with_upload_stubs(replacement) do
      result = RecordingStudioAttachable::Services::ReplaceAttachmentFile.call(
        attachment_recording: attachment_recording,
        signed_blob_id: replacement.signed_id,
        actor: Object.new
      )
    end

    assert result.success?
    assert_equal [40], handle_amounts
    assert_equal 10, RecordingStudioAttachable.storage_bytes_for(root_for(root_id))
  end

  def test_metadata_revision_does_not_claim_capacity
    install_stripe!(remaining: 0)
    @handle = PlanHandle.new(remaining: 0, error: RecordingStudioStripe::PlanLimitReached.new)
    @configuration.storage_limit = :storage_bytes
    root_id = SecureRandom.uuid
    blob_id = insert_blob(byte_size: 10)
    attachment_id = insert_attachment(byte_size: 10, root_recording_id: root_id)
    insert_link(attachment_id, blob_id)
    blob = BlobDouble.new(id: blob_id, byte_size: 10)
    attachment_recording = attachment_recording_for(root_id, attachment_id, blob: blob)

    result = nil
    RecordingStudioAttachable::Authorization.stub(:authorize!, true) do
      RecordingStudio.stub(:record!, Struct.new(:recording).new(Struct.new(:id).new("revised"))) do
        RecordingStudioAttachable::Attachment.stub(:build_from_blob, attachment_double(10)) do
          result = RecordingStudioAttachable::Services::ReviseAttachmentMetadata.call(
            attachment_recording: attachment_recording,
            actor: Object.new,
            name: "Renamed"
          )
        end
      end
    end

    assert result.success?
    assert_empty handle_amounts
    assert_equal 10, RecordingStudioAttachable.storage_bytes_for(root_for(root_id))
  end

  private

  def attachment_recording_model
    RecordingStudioAttachable::StorageLimit.install_release_hook!(RecordingRow)
    RecordingRow
  end

  def capture_attachable_error
    yield
    flunk "expected RecordingStudioAttachable::Error"
  rescue RecordingStudioAttachable::Error => e
    e
  end

  def with_test_storage_service
    return yield unless ActiveStorage::Blob.respond_to?(:services=)

    previous = ActiveStorage::Blob.services
    directory = Dir.mktmpdir("attachable-storage")
    ActiveStorage::Blob.services = previous.merge(
      "test" => ActiveStorage::Service::DiskService.new(root: directory)
    )
    yield
  ensure
    ActiveStorage::Blob.services = previous if previous
    FileUtils.remove_entry(directory) if directory
  end

  def with_recording_transaction
    has_recording = defined?(RecordingStudio::Recording)
    previous = RecordingStudio::Recording if has_recording
    has_transaction = has_recording && previous.respond_to?(:transaction)
    swapped = false
    unless has_transaction
      RecordingStudio.send(:remove_const, :Recording) if has_recording
      recording = Class.new(ActiveRecord::Base) do
        self.table_name = "recording_studio_recordings"
      end
      RecordingStudio.const_set(:Recording, recording)
      swapped = true
    end
    yield
  ensure
    if swapped
      RecordingStudio.send(:remove_const, :Recording)
      RecordingStudio.const_set(:Recording, previous) if has_recording
    end
  end

  def connect!
    ActiveRecord::Base.establish_connection(DATABASE_URL)
    ActiveRecord::Base.connection
    RecordingStudioAttachable::Attachment.reset_column_information
  end

  def connection
    ActiveRecord::Base.connection
  end

  def upload(parent, blob, max_file_size: nil)
    result = nil
    options = max_file_size ? { max_file_size: max_file_size } : {}
    RecordingStudio.stub(:capability_options, options) do
      with_upload_stubs(blob) do
        result = RecordingStudioAttachable::Services::RecordAttachmentUpload.call(
          parent_recording: parent,
          signed_blob_id: blob.signed_id,
          actor: Object.new,
          name: "Upload"
        )
      end
    end
    result
  end

  def upload_batch(parent, blobs)
    signed = blobs.to_h { |blob| [blob.signed_id, blob] }
    result = nil
    RecordingStudioAttachable::Authorization.stub(:authorize!, true) do
      ActiveStorage::Blob.stub(:find_signed!, ->(signed_id) { signed.fetch(signed_id) }) do
        RecordingStudioAttachable::Attachment.stub(:build_from_blob, attachment_double(10)) do
          RecordingStudio.stub(:record!, lambda { |**|
            @record_calls += 1
            Struct.new(:recording).new(Struct.new(:id).new("batch-#{@record_calls}"))
          }) do
            result = RecordingStudioAttachable::Services::RecordAttachmentUploads.call(
              parent_recording: parent,
              actor: Object.new,
              attachments: blobs.map { |blob| { signed_blob_id: blob.signed_id, name: blob.signed_id } }
            )
          end
        end
      end
    end
    result
  end

  def import_one(parent, blob)
    RecordingStudioAttachable::Authorization.stub(:authorize!, true) do
      ActiveStorage::Blob.stub(:create_and_upload!, blob) do
        ActiveStorage::Blob.stub(:find_signed!, blob) do
          RecordingStudioAttachable::Attachment.stub(:build_from_blob, attachment_double(blob.byte_size)) do
            RecordingStudio.stub(:record!, lambda { |**|
              @record_calls += 1
              Struct.new(:recording).new(attachment_double(blob.byte_size))
            }) do
              RecordingStudioAttachable::Services::ImportAttachment.call(
                parent_recording: parent,
                io: StringIO.new("x"),
                filename: "notes.png",
                content_type: blob.content_type,
                actor: Object.new,
                identify: false
              )
            end
          end
        end
      end
    end
  end

  def with_upload_stubs(blob, &block)
    @record_calls = 0
    RecordingStudioAttachable::Authorization.stub(:authorize!, true) do
      ActiveStorage::Blob.stub(:find_signed!, blob) do
        RecordingStudioAttachable::Attachment.stub(:build_from_blob, attachment_double(blob.byte_size)) do
          RecordingStudio.stub(:record!, lambda { |**|
            @record_calls += 1
            Struct.new(:recording).new(attachment_double(blob.byte_size))
          }, &block)
        end
      end
    end
  end

  def attachment_double(byte_size)
    Struct.new(:id, :name, :attachment_kind, :original_filename, :content_type, :byte_size).new(
      "attachment-1", "Upload", "image", "file.png", "image/png", byte_size
    )
  end

  def parent_recording
    root = root_for(SecureRandom.uuid)
    test = self
    root.define_singleton_method(:billing) do
      test.send(:billing_for, test.instance_variable_get(:@handle))
    end
    Struct.new(:id, :recordable_type, :root_recording).new(SecureRandom.uuid, "Workspace", root)
  end

  def root_for(id)
    Struct.new(:id).new(id)
  end

  def billing_for(handle)
    handle_ref = handle
    billing = Object.new
    billing.define_singleton_method(:limit) { |_name| handle_ref }
    billing
  end

  def handle_amounts
    @handle&.amounts || []
  end

  def install_stripe!(remaining:, error: nil)
    remove_stripe!
    stripe = Module.new
    Object.const_set(:RecordingStudioStripe, stripe)
    error_class = Class.new(StandardError)
    plan_class = Class.new(error_class) do
      attr_reader :handle

      def initialize(handle: nil, message: "Pick a plan to add storage.")
        @handle = handle
        super(message)
      end
    end
    stripe.const_set(:Error, error_class)
    stripe.const_set(:PlanLimitReached, plan_class)
    limits = Class.new do
      def self.known?(name)
        %w[storage_bytes counted_items].include?(name.to_s)
      end

      def self.fetch(name)
        key = name.to_s
        raise ArgumentError, "Unknown limit #{key}" unless known?(key)

        definition = Object.new
        quantity = key == "storage_bytes"
        definition.define_singleton_method(:quantity?) { quantity }
        definition.define_singleton_method(:name) { key }
        definition
      end
    end
    stripe.const_set(:Limits, limits)
    configuration = Object.new
    usages = {}
    configuration.define_singleton_method(:register_limit_usage) do |name, &block|
      usages[name.to_s] = block
    end
    configuration.define_singleton_method(:limit_usage_for) { |name| usages[name.to_s] }
    stripe.define_singleton_method(:configuration) { configuration }
    stripe.define_singleton_method(:register_limit_usage) do |name, &block|
      configuration.register_limit_usage(name, &block)
    end
    @handle = PlanHandle.new(remaining: remaining, error: error)
  end

  def remove_stripe!
    Object.send(:remove_const, :RecordingStudioStripe) if defined?(RecordingStudioStripe)
    @handle = nil
  end

  def stub_recording_studio!
    studio = RecordingStudio
    return if studio.respond_to?(:capability_options)

    studio.define_singleton_method(:capability_options) { |_name, _for_type: nil, **| {} }
  end

  def insert_blob(byte_size:)
    id = connection.select_value(<<~SQL)
      INSERT INTO active_storage_blobs (id, key, filename, content_type, service_name, byte_size, created_at)
      VALUES (gen_random_uuid(), #{connection.quote(SecureRandom.hex(12))}, 'file.png', 'image/png', 'test', #{byte_size.to_i}, NOW())
      RETURNING id
    SQL
    @created_ids[:blobs] << id
    id
  end

  def insert_attachment(byte_size:, root_recording_id:)
    id = connection.select_value(<<~SQL)
      INSERT INTO recording_studio_attachable_attachments
        (id, name, attachment_kind, original_filename, content_type, byte_size, root_recording_id)
      VALUES (
        gen_random_uuid(),
        'file',
        'file',
        'file.png',
        'image/png',
        #{byte_size.to_i},
        #{root_recording_id.nil? ? 'NULL' : connection.quote(root_recording_id)}
      )
      RETURNING id
    SQL
    @created_ids[:attachments] << id
    id
  end

  def insert_link(attachment_id, blob_id)
    id = connection.select_value(<<~SQL)
      INSERT INTO active_storage_attachments (id, name, record_type, record_id, blob_id, created_at)
      VALUES (
        gen_random_uuid(),
        'file',
        'RecordingStudioAttachable::Attachment',
        #{connection.quote(attachment_id)},
        #{connection.quote(blob_id)},
        NOW()
      )
      RETURNING id
    SQL
    @created_ids[:links] << id
    id
  end

  def insert_variant(blob_id)
    connection.select_value(<<~SQL)
      INSERT INTO active_storage_variant_records (id, blob_id, variation_digest)
      VALUES (gen_random_uuid(), #{connection.quote(blob_id)}, #{connection.quote(SecureRandom.hex(8))})
      RETURNING id
    SQL
  end

  def insert_recording(recordable_type:, recordable_id: nil, root_recording_id: nil, parent_recording_id: nil)
    recordable_id ||= connection.select_value("SELECT gen_random_uuid()")
    id = connection.select_value(<<~SQL)
      INSERT INTO recording_studio_recordings
        (id, recordable_type, recordable_id, root_recording_id, parent_recording_id, created_at, updated_at)
      VALUES (
        gen_random_uuid(),
        #{connection.quote(recordable_type)},
        #{connection.quote(recordable_id)},
        #{root_recording_id.nil? ? 'NULL' : connection.quote(root_recording_id)},
        #{parent_recording_id.nil? ? 'NULL' : connection.quote(parent_recording_id)},
        NOW(),
        NOW()
      )
      RETURNING id
    SQL
    @created_ids[:recordings] << id
    id
  end

  def insert_event(recording_id:, recordable_id:, previous_recordable_id:)
    id = connection.select_value(<<~SQL)
      INSERT INTO recording_studio_events
        (id, action, created_at, occurred_at, recordable_id, recordable_type, recording_id,
         previous_recordable_id, previous_recordable_type, metadata)
      VALUES (
        gen_random_uuid(),
        'attachment_metadata_revised',
        NOW(),
        NOW(),
        #{connection.quote(recordable_id)},
        'RecordingStudioAttachable::Attachment',
        #{connection.quote(recording_id)},
        #{connection.quote(previous_recordable_id)},
        'RecordingStudioAttachable::Attachment',
        '{}'::jsonb
      )
      RETURNING id
    SQL
    @created_ids[:events] << id
    id
  end

  def attachment_root(id)
    connection.select_value(<<~SQL)
      SELECT root_recording_id FROM recording_studio_attachable_attachments WHERE id = #{connection.quote(id)}
    SQL
  end

  def attachment_recording_for(root_id, attachment_id, blob: nil)
    root = root_for(root_id)
    billing = billing_for(@handle)
    root.define_singleton_method(:billing) { billing }
    parent = Struct.new(:id, :recordable_type, :root_recording).new(SecureRandom.uuid, "Workspace", root)
    recordable = Struct.new(:id, :name, :description, :caption, :credit, :alt_text, :file).new(
      attachment_id,
      "Old",
      "Desc",
      nil,
      nil,
      nil,
      Struct.new(:blob).new(blob)
    )
    Struct.new(:id, :recordable_type, :parent_recording, :parent_recording_id, :recordable, :root_recording).new(
      SecureRandom.uuid,
      "RecordingStudioAttachable::Attachment",
      parent,
      parent.id,
      recordable,
      root
    )
  end

  def delete_created_rows
    return unless defined?(ActiveRecord::Base) && ActiveRecord::Base.connected?

    @created_ids[:events].each do |id|
      connection.execute("DELETE FROM recording_studio_events WHERE id = #{connection.quote(id)}")
    end
    @created_ids[:links].each do |id|
      connection.execute("DELETE FROM active_storage_attachments WHERE id = #{connection.quote(id)}")
    end
    @created_ids[:recordings].each do |id|
      connection.execute("DELETE FROM recording_studio_recordings WHERE id = #{connection.quote(id)}")
    end
    @created_ids[:attachments].each do |id|
      connection.execute("DELETE FROM recording_studio_attachable_attachments WHERE id = #{connection.quote(id)}")
    end
    @created_ids[:blobs].each do |id|
      connection.execute("DELETE FROM active_storage_variant_records WHERE blob_id = #{connection.quote(id)}")
      connection.execute("DELETE FROM active_storage_blobs WHERE id = #{connection.quote(id)}")
    end
  rescue StandardError
    nil
  end
end
