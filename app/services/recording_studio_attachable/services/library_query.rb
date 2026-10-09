# frozen_string_literal: true

module RecordingStudioAttachable
  module Services
    module LibraryQuery
      DEFAULT_NAME = "Library"
      DEFAULT_IDEMPOTENCY_PREFIX = "recording-studio-attachable-library:default"

      module_function

      def live_for_parent(parent)
        return [] if parent.blank?

        recordings_for(parent_recording_id: parent.id).select { |recording| live?(recording) }
      end

      def live_in_root(recording)
        root = root_for(recording)
        return [] if root.blank?

        recordings_for(root_recording_id: root.id).select { |library| live?(library) }
      end

      def default_for_parent(parent)
        live = live_for_parent(parent)
        live.find { |recording| default?(recording) } || (live.one? ? live.first : nil)
      end

      def trashed_default_for_parent(parent)
        return if parent.blank?

        recordings_for(parent_recording_id: parent.id).find do |recording|
          recording.try(:trashed_at).present? && default?(recording)
        end
      end

      def title_for(library_recording)
        recordable = library_recording.try(:recordable)
        %i[title name].each do |method_name|
          next unless recordable.respond_to?(method_name)

          value = recordable.public_send(method_name).to_s.strip
          return value if value.present?
        end

        DEFAULT_NAME
      end

      def default?(library_recording)
        recordable = library_recording.try(:recordable)
        return false unless recordable.respond_to?(:default)

        recordable.default
      end

      def live?(recording)
        Placements.library_recording?(recording) && recording.try(:trashed_at).blank?
      end

      def root_for(recording)
        return if recording.blank?
        return recording unless recording.respond_to?(:root_recording)

        recording.root_recording || recording
      end

      def default_idempotency_key(parent)
        "#{DEFAULT_IDEMPOTENCY_PREFIX}:#{parent.id}"
      end

      def recordings_for(**attributes)
        relation = RecordingStudio::Recording.where(
          recordable_type: Placements::LIBRARY_TYPE,
          **attributes
        )
        return Array(relation) unless relation.respond_to?(:includes)

        relation = relation.includes(:recordable) if relation.respond_to?(:includes)
        relation = relation.order(:created_at, :id) if relation.respond_to?(:order)
        relation.to_a
      rescue StandardError
        []
      end
    end
  end
end
