# frozen_string_literal: true

module RecordingStudioAttachable
  # Hard-destroys attachment child recordings before core's
  # `dependent: :restrict_with_error` on `child_recordings` can abort.
  module DestroyAttachmentChildren
    NOTIFICATION = "destroy_children.recording_studio_attachable"
    ATTACHMENT_TYPE = "RecordingStudioAttachable::Attachment"
    RECORDABLE_DESTROY_DEPENDENTS = %i[destroy destroy_async delete].freeze

    module OnRecording
      extend ActiveSupport::Concern

      included do
        before_destroy :recording_studio_attachable_destroy_attachment_children, prepend: true
      end

      def recording_studio_attachable_destroy_attachment_children
        RecordingStudioAttachable::DestroyAttachmentChildren.call(self)
      end
    end

    class << self
      def register!
        return if @registered

        @registered = true
        RecordingStudio.configuration.hooks.extend_model(:recording) do
          include RecordingStudioAttachable::DestroyAttachmentChildren::OnRecording
        end
      end

      def call(recording)
        children = attachment_children(recording).to_a
        return if children.empty?

        recordable_ids = children.flat_map { |child| version_ids(child) }.uniq
        children.each(&:destroy!)
        destroy_unreferenced_recordables!(recordable_ids)
        recording.association(:child_recordings).reset
        notify_destroyed(recording, children.size)
      end

      # True when some recording other than `except_recording` still points at
      # this attachment snapshot, including an earlier revision in its history.
      def referenced_elsewhere?(recordable_id, except_recording:)
        return false if recordable_id.blank? || !recording_models_loaded?
        return true if other_recordings(recordable_id, except_recording).exists?

        event_references?(recordable_id, except_recording: except_recording)
      end

      # `delegated_type :recordable` is a belongs_to with no dependent option,
      # so Recording#destroy! leaves the recordable row in place.
      def recording_destroys_recordable?
        reflection = RecordingStudio::Recording.reflect_on_association(:recordable)
        return false unless reflection

        RECORDABLE_DESTROY_DEPENDENTS.include?(reflection.options[:dependent])
      end

      private

      def notify_destroyed(recording, count)
        ActiveSupport::Notifications.instrument(
          NOTIFICATION,
          parent_recording_id: recording.id,
          count: count
        )
      end

      def recording_models_loaded?
        defined?(RecordingStudio::Recording) && defined?(RecordingStudio::Event)
      end

      def other_recordings(recordable_id, except_recording)
        recordings = RecordingStudio::Recording.unscoped.where(
          recordable_type: ATTACHMENT_TYPE,
          recordable_id: recordable_id
        )
        return recordings if except_recording&.id.blank?

        recordings.where.not(id: except_recording.id)
      end

      def attachment_children(recording)
        RecordingStudio::Recording.unscoped.where(
          parent_recording_id: recording.id,
          recordable_type: ATTACHMENT_TYPE
        )
      end

      def version_ids(recording)
        ids = []
        ids << recording.recordable_id if recording.recordable_id.present?
        event_rows(recording).each do |recordable_id, recordable_type, previous_id, previous_type|
          ids << recordable_id if recordable_type == ATTACHMENT_TYPE && recordable_id.present?
          ids << previous_id if previous_type == ATTACHMENT_TYPE && previous_id.present?
        end
        ids
      end

      def event_rows(recording)
        RecordingStudio::Event.unscoped.where(recording_id: recording.id).pluck(
          :recordable_id,
          :recordable_type,
          :previous_recordable_id,
          :previous_recordable_type
        )
      end

      def destroy_unreferenced_recordables!(recordable_ids)
        return if recording_destroys_recordable?

        recordable_ids.uniq.each do |recordable_id|
          next if referenced_elsewhere?(recordable_id, except_recording: nil)

          recordable = RecordingStudioAttachable::Attachment.find_by(id: recordable_id)
          next unless recordable

          # Recordables raise on destroy!. Release the file, then delete the row.
          release_file!(recordable)
          recordable.delete
        end
      end

      def release_file!(recordable)
        return unless recordable.file.attached?

        blob = recordable.file.blob
        recordable.file.detach
        return if blob.attachments.exists?

        blob.purge
      end

      def event_references?(recordable_id, except_recording:)
        scope = RecordingStudio::Event.unscoped
        scope = scope.where.not(recording_id: except_recording.id) if except_recording&.id.present?

        scope.where(recordable_type: ATTACHMENT_TYPE, recordable_id: recordable_id).or(
          scope.where(previous_recordable_type: ATTACHMENT_TYPE, previous_recordable_id: recordable_id)
        ).exists?
      end
    end
  end
end
