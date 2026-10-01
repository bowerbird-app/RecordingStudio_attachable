# frozen_string_literal: true

module RecordingStudioAttachable
  class StorageLimit
    RESERVATIONS = :recording_studio_attachable_storage_reservations
    DISCARDS = :recording_studio_attachable_storage_discards
    DISCARD_DEPTH = :recording_studio_attachable_storage_discard_depth
    ATTACHMENT_TYPE = "RecordingStudioAttachable::Attachment"

    class IncomingBytes
      def self.for(root, blobs)
        new(root, blobs)
      end

      def initialize(root, blobs)
        @root = root
        @blobs = Array(blobs)
        @amount = nil
        @amount_computed = false
      end

      attr_reader :root, :blobs

      def amount
        return @amount if @amount_computed

        @amount_computed = true
        @amount = compute_amount
      end

      def blob_ids
        blobs.map { |blob| self.class.identity(blob) }
      end

      def for_root?(other)
        mine = self.class.root_key(root)
        theirs = self.class.root_key(other)
        return root.equal?(other) if mine.nil? || theirs.nil?

        mine == theirs
      end

      def self.identity(blob)
        id = blob.id if blob.respond_to?(:id)
        id.nil? ? blob.object_id : id
      end

      def self.root_key(root)
        return if root.blank? || !root.respond_to?(:id) || root.id.blank?

        root.id.to_s
      end

      def self.persisted?(blob)
        return false unless blob.respond_to?(:id) && blob.id.present?
        return blob.persisted? if blob.respond_to?(:persisted?)

        true
      end

      private

      def compute_amount
        return 0 unless StorageLimit.enabled?

        retained = StorageLimit.retained_blob_ids(root).map(&:to_s)
        seen = {}
        blobs.sum do |blob|
          increment_for(blob, retained, seen)
        end
      end

      def increment_for(blob, retained, seen)
        raise StorageLimitError, "Cannot check storage for an unsaved blob" unless self.class.persisted?(blob)

        size = blob.byte_size.to_i
        return 0 if size <= 0

        id = blob.id.to_s
        return 0 if seen[id]

        seen[id] = true
        return 0 if retained.include?(id)

        size
      end
    end

    class << self
      def bytes_for(root)
        root_key = IncomingBytes.root_key(root)
        return 0 if root_key.blank?

        file_blob_scope(root_key).sum(:byte_size).to_i
      end

      def retained_blob_ids(root)
        root_key = IncomingBytes.root_key(root)
        return [] if root_key.blank?

        file_links(root_key).distinct.pluck(:blob_id)
      end

      def install_release_hook!(klass = nil)
        target = klass || recording_class
        return unless target.respond_to?(:include)
        return if target.include?(StorageRelease)

        target.include StorageRelease
      end

      def detach_recording!(recording)
        return unless attachment_recording?(recording)

        recording.recording_studio_attachable_detached_blob_ids = detach_file_links!(attachment_ids_for(recording))
      end

      def purge_detached_blobs!(recording)
        ids = recording.recording_studio_attachable_detached_blob_ids
        return if ids.blank?
        return unless defined?(ActiveStorage::Blob) && ActiveStorage::Blob.respond_to?(:where)

        ActiveStorage::Blob.where(id: ids).find_each do |blob|
          next if blob_attached?(blob)

          blob.purge
        end
      end

      def with_storage_capacity!(root_recording, incoming_bytes, &block)
        incoming = incoming_for!(root_recording, incoming_bytes)
        case reserved_coverage(root_recording, incoming)
        when :covered
          return block.call
        when :outside
          raise StorageLimitError, "Storage claim includes blobs outside the current reservation"
        end

        reserve_and_claim(root_recording, incoming, &block)
      end

      def tracking_discards(&)
        depth = execution_state[DISCARD_DEPTH].to_i
        execution_state[DISCARD_DEPTH] = depth + 1
        execution_state[DISCARDS] ||= []
        run_discard_scope(depth, &)
      end

      def discard_unattached!(blobs)
        Array(blobs).each { |blob| discard_one_unattached(blob) }
      end

      def register_usage!
        return unless enabled?

        name = RecordingStudioAttachable.configuration.storage_limit
        RecordingStudioStripe.register_limit_usage(name) do |root|
          RecordingStudioAttachable.storage_bytes_for(root)
        end
      end

      def enabled?
        RecordingStudioAttachable.configuration.storage_limit.present? && defined?(RecordingStudioStripe)
      end

      def reset!
        execution_state[RESERVATIONS] = nil
        execution_state[DISCARDS] = nil
        execution_state[DISCARD_DEPTH] = nil
      end

      private

      def claim(root_recording, incoming, &block)
        return block.call if incoming.amount.zero? || !enabled?

        register_usage!
        limit_handle(root_recording).with_capacity!(incoming.amount, &block)
      end

      def reserved_coverage(root_recording, incoming)
        current = reservation_ids(root_recording)
        return if current.nil?
        return :covered if (incoming.blob_ids - current).empty?

        :outside
      end

      def reserve_and_claim(root_recording, incoming, &)
        push_reservation(root_recording, incoming.blob_ids)
        begin
          claim(root_recording, incoming, &)
        rescue StandardError => e
          hold_unattached_until_transaction_exits(e, incoming.blobs)
          raise
        ensure
          pop_reservation(root_recording)
        end
      end

      def run_discard_scope(depth, &block)
        block.call
      rescue StandardError => e
        begin
          release_remembered_discards(e)
        ensure
          raise e
        end
      ensure
        execution_state[DISCARD_DEPTH] = depth
        execution_state[DISCARDS] = nil if depth.zero?
      end

      def release_remembered_discards(error)
        return unless plan_limit?(error)
        return if recording_transaction_open?

        discard_unattached!(execution_state[DISCARDS])
      end

      def incoming_for!(root_recording, incoming_bytes)
        return incoming_bytes if incoming_bytes.is_a?(IncomingBytes) && incoming_bytes.for_root?(root_recording)

        raise StorageLimitError, "Storage capacity requires IncomingBytes for this root"
      end

      def limit_handle(root_recording)
        name = RecordingStudioAttachable.configuration.storage_limit
        quantity_definition!(name)
        root_recording.billing.limit(name)
      rescue StorageLimitUnknown
        raise
      rescue ArgumentError
        raise StorageLimitUnknown, "Unknown storage limit #{name}"
      end

      def quantity_definition!(name)
        limits = RecordingStudioStripe::Limits
        raise StorageLimitUnknown, "Unknown storage limit #{name}" unless limits.known?(name)

        definition = limits.fetch(name)
        raise StorageLimitUnknown, "Storage limit #{name} is not a quantity limit" unless definition.quantity?

        definition
      end

      def hold_unattached_until_transaction_exits(error, blobs)
        return unless plan_limit?(error)

        if recording_transaction_open?
          remember_discards(blobs)
        else
          discard_unattached!(blobs)
        end
      rescue StandardError
        raise error
      end

      def plan_limit?(error)
        defined?(RecordingStudioStripe::PlanLimitReached) && error.is_a?(RecordingStudioStripe::PlanLimitReached)
      end

      def remember_discards(blobs)
        execution_state[DISCARDS] ||= []
        execution_state[DISCARDS].concat(Array(blobs))
      end

      def discard_one_unattached(blob)
        return if blob.blank? || !blob.respond_to?(:purge)
        return if blob_attached?(blob)

        blob.purge
      end

      def blob_attached?(blob)
        return false unless blob.respond_to?(:attachments)

        attachments = blob.attachments
        return false if attachments.blank? || !attachments.respond_to?(:exists?)

        attachments.exists?
      end

      def recording_transaction_open?
        recording_connection&.transaction_open? || false
      rescue StandardError
        false
      end

      def recording_connection
        return unless defined?(RecordingStudio::Recording)

        klass = RecordingStudio::Recording
        return unless klass.respond_to?(:connection_pool)

        pool = klass.connection_pool
        pool.active_connection if pool.active_connection?
      end

      def reservation_ids(root)
        sets = reservations[IncomingBytes.root_key(root) || root.object_id]
        return if sets.blank?

        sets.flatten
      end

      def push_reservation(root, ids)
        key = IncomingBytes.root_key(root) || root.object_id
        reservations[key] ||= []
        reservations[key] << ids
      end

      def pop_reservation(root)
        key = IncomingBytes.root_key(root) || root.object_id
        sets = reservations[key]
        return if sets.blank?

        sets.pop
        reservations.delete(key) if sets.empty?
      end

      def reservations
        execution_state[RESERVATIONS] ||= {}
      end

      def execution_state
        defined?(ActiveSupport::IsolatedExecutionState) ? ActiveSupport::IsolatedExecutionState : Thread.current
      end

      def recording_class
        return unless defined?(RecordingStudio)

        klass = RecordingStudio.const_get(:Recording)
        klass if klass.is_a?(Class) && klass < ActiveRecord::Base
      rescue NameError
        nil
      end

      def attachment_recording?(recording)
        recording.respond_to?(:recordable_type) && recording.recordable_type == ATTACHMENT_TYPE
      end

      def attachment_ids_for(recording)
        ids = []
        ids << recording.recordable_id if recording.respond_to?(:recordable_id) && recording.recordable_id.present?
        ids.concat(event_attachment_ids(recording))
        ids.map(&:to_s).uniq
      end

      def event_attachment_ids(recording)
        return [] unless recording.respond_to?(:events)

        event_rows(recording).flat_map { |row| attachment_ids_from_event_row(row) }
      end

      def event_rows(recording)
        scope = recording.association(:events).scope
        scope = scope.unscope(:order) if scope.respond_to?(:unscope)
        scope.pluck(:recordable_id, :recordable_type, :previous_recordable_id, :previous_recordable_type)
      end

      def attachment_ids_from_event_row(row)
        recordable_id, recordable_type, previous_id, previous_type = row
        ids = []
        ids << recordable_id if attachment_reference?(recordable_type, recordable_id)
        ids << previous_id if attachment_reference?(previous_type, previous_id)
        ids
      end

      def attachment_reference?(type, id)
        type == ATTACHMENT_TYPE && id.present?
      end

      def detach_file_links!(attachment_ids)
        return [] if attachment_ids.blank?
        return [] unless defined?(ActiveStorage::Attachment) && ActiveStorage::Attachment.respond_to?(:where)

        links = ActiveStorage::Attachment.where(
          record_type: ATTACHMENT_TYPE,
          name: "file",
          record_id: attachment_ids
        )
        blob_ids = links.distinct.pluck(:blob_id)
        links.delete_all
        blob_ids
      end

      def file_links(root_key)
        ActiveStorage::Attachment.where(
          record_type: ATTACHMENT_TYPE,
          name: "file",
          record_id: RecordingStudioAttachable::Attachment.where(root_recording_id: root_key).select(:id)
        )
      end

      def file_blob_scope(root_key)
        ActiveStorage::Blob.where(id: file_links(root_key).select(:blob_id))
      end
    end
  end
end
