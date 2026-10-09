# frozen_string_literal: true

module RecordingStudioAttachable
  module Services
    module LibraryQuery
      DEFAULT_KEY = "default"
      KEY_PATTERN = /\A[a-z][a-z0-9_]*\z/
      IDEMPOTENCY_PREFIX = "recording-studio-attachable-library"

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

      def for_parent_and_key(parent, key)
        normalized = normalize_key(key)
        live_for_parent(parent).find { |recording| key_for(recording) == normalized }
      end

      def trashed_for_parent_and_key(parent, key)
        return if parent.blank?

        normalized = normalize_key(key)
        recordings_for(parent_recording_id: parent.id).find do |recording|
          recording.try(:trashed_at).present? && key_for(recording) == normalized
        end
      end

      def key_for(library_recording)
        recordable = library_recording.try(:recordable)
        return DEFAULT_KEY unless recordable.respond_to?(:key)

        normalize_key(recordable.key)
      rescue ArgumentError
        DEFAULT_KEY
      end

      def title_for(library_recording)
        label_for_key(key_for(library_recording))
      end

      def label_for_key(key)
        normalized = begin
          normalize_key(key)
        rescue ArgumentError
          key.to_s.strip.downcase.presence || DEFAULT_KEY
        end

        resolver = RecordingStudioAttachable.configuration.library_label
        resolver.call(normalized).to_s.strip.presence || humanized_key(normalized)
      rescue StandardError
        humanized_key(normalized || DEFAULT_KEY)
      end

      def normalize_key(key)
        return DEFAULT_KEY if key.nil?

        value = key.to_s.strip.downcase
        return DEFAULT_KEY if value.blank?
        raise ArgumentError, "Use a simple library key, like campaign" unless value.match?(KEY_PATTERN)

        value
      end

      def humanized_key(key)
        key.to_s.tr("_", " ").capitalize
      end

      def live?(recording)
        Placements.library_recording?(recording) && recording.try(:trashed_at).blank?
      end

      def root_for(recording)
        return if recording.blank?
        return recording unless recording.respond_to?(:root_recording)

        recording.root_recording || recording
      end

      def image_library_parent_for(recording)
        current = recording
        while current
          return current if library_enabled?(current)

          next_parent = current.try(:parent_recording)
          break if next_parent.blank? || next_parent == current

          current = next_parent
        end

        root_for(recording)
      end

      def idempotency_key(parent, key)
        "#{IDEMPOTENCY_PREFIX}:#{normalize_key(key)}:#{parent.id}"
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

      def library_enabled?(recording)
        RecordingStudioAttachable::Authorization.library_enabled?(recording: recording)
      rescue StandardError
        false
      end
    end
  end
end
