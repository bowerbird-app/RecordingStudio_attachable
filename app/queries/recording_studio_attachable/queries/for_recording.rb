# frozen_string_literal: true

module RecordingStudioAttachable
  module Queries
    class ForRecording
      DEFAULT_PER_PAGE = 24
      MAX_PER_PAGE = 100
      SCOPES = %i[direct subtree].freeze
      KIND_FILTERS = {
        all: nil,
        images: "image",
        files: "file"
      }.freeze

      class << self
        def normalize_scope(scope)
          candidate = scope.presence&.to_sym
          return candidate if SCOPES.include?(candidate)

          RecordingStudioAttachable.configuration.default_listing_scope.to_sym
        end

        def normalize_kind(kind)
          candidate = kind.presence&.to_sym
          return candidate if KIND_FILTERS.key?(candidate)

          RecordingStudioAttachable.configuration.default_kind_filter.to_sym
        end

        def normalize_search(search)
          search.to_s.strip.presence
        end

        def normalize_page(page)
          candidate = page.to_i
          candidate.positive? ? candidate : 1
        end

        def normalize_per_page(per_page)
          candidate = per_page.to_i
          candidate = DEFAULT_PER_PAGE unless candidate.positive?
          [candidate, MAX_PER_PAGE].min
        end
      end

      attr_reader :current_page, :per_page, :search, :total_count

      def initialize(recording:, scope: nil, kind: nil, include_trashed: false, search: nil, page: nil, per_page: nil)
        @recording = recording
        @scope = self.class.normalize_scope(scope)
        @kind = self.class.normalize_kind(kind)
        @include_trashed = include_trashed
        @search = self.class.normalize_search(search)
        @current_page = self.class.normalize_page(page)
        @per_page = self.class.normalize_per_page(per_page)
        @total_count = 0
      end

      def call
        relation = base_relation
        @total_count = relation.count
        @current_page = [current_page, total_pages].min

        relation
          .order(created_at: :desc, id: :desc)
          .limit(per_page)
          .offset((current_page - 1) * per_page)
          .includes(recordable: [{ file_attachment: :blob }])
      end

      def total_pages
        return 1 if total_count.zero?

        (total_count.to_f / per_page).ceil
      end

      def next_page?
        current_page < total_pages
      end

      def previous_page?
        current_page > 1
      end

      private

      attr_reader :recording, :scope, :kind, :include_trashed

      def base_relation
        relation = recording.recordings_query(
          include_children: true,
          type: RecordingStudioAttachable::Attachment.name,
          parent_id: direct_scope? ? recording.id : nil,
          recordable_filters: recordable_filters
        )
        relation = relation.where(trashed_at: nil) unless include_trashed
        relation = relation.where(recordable_id: matching_attachment_ids) if search.present?
        relation
      end

      def direct_scope?
        scope != :subtree
      end

      def recordable_filters
        kind_value = KIND_FILTERS.fetch(kind, nil)
        return {} if kind_value.blank?

        { attachment_kind: kind_value }
      end

      def matching_attachment_ids
        pattern = "%#{ActiveRecord::Base.sanitize_sql_like(search.downcase)}%"
        RecordingStudioAttachable::Attachment.where("LOWER(name) LIKE ?", pattern).select(:id)
      end
    end
  end
end
