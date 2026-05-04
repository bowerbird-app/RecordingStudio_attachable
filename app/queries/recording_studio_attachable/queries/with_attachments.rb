# frozen_string_literal: true

module RecordingStudioAttachable
  module Queries
    class WithAttachments
      def initialize(scope: RecordingStudio::Recording.all, include_trashed: false)
        @scope = scope
        @include_trashed = include_trashed
      end

      def call
        attachment_scope = RecordingStudio::Recording.unscoped.where(recordable_type: RecordingStudioAttachable::Attachment.name)
        attachment_scope = attachment_scope.where(trashed_at: nil) unless include_trashed
        scope.where(id: attachment_scope.select(:parent_recording_id).distinct)
      end

      private

      attr_reader :scope, :include_trashed
    end
  end
end
