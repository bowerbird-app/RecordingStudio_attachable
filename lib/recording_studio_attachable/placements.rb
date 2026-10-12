# frozen_string_literal: true

module RecordingStudioAttachable
  module Placements
    ATTACHMENT_TYPE = "RecordingStudioAttachable::Attachment"

    Resolved = Struct.new(
      :placement_recording,
      :attachment_recording,
      :attachment,
      :item_recording,
      :item,
      :adapter,
      keyword_init: true
    )
    Usage = Struct.new(:placement_recording, :parent_recording, :label, keyword_init: true)

    class << self
      def resolve(parent_recording, include_trashed_images: false, **options)
        wrap_resolved(
          RecordingStudioLibrary.resolve(
            parent_recording,
            include_trashed: include_trashed_images,
            actor: actor_for_resolve(options)
          )
        )
      end

      def usage_for(attachment_recording)
        wrap_usages(RecordingStudioLibrary.usages(attachment_recording))
      end

      def usage_for_library(library_recording)
        wrap_usages(RecordingStudioLibrary.usages(library_recording))
      end

      def purge_for(item_recording)
        RecordingStudioLibrary::Placements.purge_for(item_recording)
      end

      def purge_library(library_recording)
        RecordingStudioLibrary::Placements.purge_library(library_recording)
      end

      def picker_libraries_for(parent_recording)
        resolver = RecordingStudioAttachable.configuration.placement_picker_libraries
        Array(resolver.call(parent_recording)).select { |library| live_library?(library) }
      rescue StandardError
        []
      end

      def live_library?(library)
        RecordingStudioLibrary::Services::LibraryQuery.live?(library)
      end

      def library_title(library_recording)
        RecordingStudioLibrary::Placements.library_title(library_recording)
      end

      def library_recording?(recording)
        RecordingStudioLibrary::Placements.library_recording?(recording)
      end

      def placement_recording?(recording)
        RecordingStudioLibrary::Placements.placement_recording?(recording)
      end

      def attachment_recording?(recording)
        recording.respond_to?(:recordable_type) && recording.recordable_type == ATTACHMENT_TYPE
      end

      def place_label(parent_recording)
        resolver = RecordingStudioAttachable.configuration.placement_place_label
        resolver.call(parent_recording).to_s.strip.presence || fallback_place_label(parent_recording)
      end

      def fallback_place_label(parent_recording)
        RecordingStudioLibrary::Placements.fallback_place_label(parent_recording)
      end

      private

      def actor_for_resolve(options)
        return options[:actor] if options.key?(:actor)
        return Current.actor if defined?(Current) && Current.respond_to?(:actor)

        nil
      end

      def wrap_resolved(entries)
        Array(entries).map do |entry|
          Resolved.new(
            placement_recording: entry.placement_recording,
            attachment_recording: entry.item_recording,
            attachment: entry.item,
            item_recording: entry.item_recording,
            item: entry.item,
            adapter: entry.adapter
          )
        end
      end

      def wrap_usages(entries)
        Array(entries).map do |entry|
          Usage.new(
            placement_recording: entry.placement_recording,
            parent_recording: entry.parent_recording,
            label: entry.label
          )
        end
      end
    end
  end
end
