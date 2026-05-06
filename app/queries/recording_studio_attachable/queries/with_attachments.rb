# frozen_string_literal: true

module RecordingStudioAttachable
  module Queries
    class WithAttachments
      KIND_FILTERS = {
        all: nil,
        image: "image",
        images: "image",
        file: "file",
        files: "file"
      }.freeze

      def initialize(scope: RecordingStudio::Recording.all, include_trashed: false, kind: nil, recordable_type: nil)
        @scope = scope
        @include_trashed = include_trashed
        @kind = normalize_kind(kind)
        @recordable_type = recordable_type.presence
      end

      def call
        filtered_scope = scope
        filtered_scope = filtered_scope.where(recordable_type: recordable_type) if recordable_type.present?

        attachment_scope = RecordingStudio::Recording.unscoped.where(recordable_type: RecordingStudioAttachable::Attachment.name)
        attachment_scope = attachment_scope.where(trashed_at: nil) unless include_trashed
        attachment_scope = attachment_scope.where(recordable_id: matching_attachment_ids) if kind.present?
        filtered_scope.where(id: attachment_scope.select(:parent_recording_id).distinct)
      end

      private

      attr_reader :scope, :include_trashed, :kind, :recordable_type

      def normalize_kind(value)
        KIND_FILTERS.fetch(value.to_s.strip.downcase.presence&.to_sym, nil)
      end

      def matching_attachment_ids
        RecordingStudioAttachable::Attachment.where(attachment_kind: kind).select(:id)
      end
    end
  end
end
