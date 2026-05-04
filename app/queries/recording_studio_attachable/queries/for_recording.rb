# frozen_string_literal: true

module RecordingStudioAttachable
  module Queries
    class ForRecording
      KIND_FILTERS = {
        all: nil,
        images: "image",
        files: "file"
      }.freeze

      def initialize(recording:, scope: nil, kind: nil, include_trashed: false)
        @recording = recording
        @scope = (scope || RecordingStudioAttachable.configuration.default_listing_scope).to_sym
        @kind = (kind || RecordingStudioAttachable.configuration.default_kind_filter).to_sym
        @include_trashed = include_trashed
      end

      def call
        relation = recording.recordings_query(
          include_children: true,
          type: RecordingStudioAttachable::Attachment.name,
          parent_id: direct_scope? ? recording.id : nil,
          recordable_filters: recordable_filters
        )
        relation = relation.where(trashed_at: nil) unless include_trashed
        relation.includes(recordable: [{ file_attachment: :blob }])
      end

      private

      attr_reader :recording, :scope, :kind, :include_trashed

      def direct_scope?
        scope != :subtree
      end

      def recordable_filters
        kind_value = KIND_FILTERS.fetch(kind, nil)
        return {} if kind_value.blank?

        { attachment_kind: kind_value }
      end
    end
  end
end
