# frozen_string_literal: true

module RecordingStudio
  module Capabilities
    module LibraryPlacement
      def self.to(**options)
        RecordingStudio::Capabilities.include_for(:library_placement, **options)
      end

      module RecordingMethods
        include RecordingStudio::Capability if defined?(RecordingStudio::Capability)

        def place_library_image(**options)
          assert_library_placement_capability!
          RecordingStudioAttachable::Services::PlaceLibraryImage.call(parent_recording: self, **options).value
        end

        def upload_to_library_and_place(**options)
          assert_library_placement_capability!
          RecordingStudioAttachable::Services::UploadToLibraryAndPlace.call(parent_recording: self, **options).value
        end

        def library_placements(include_trashed_images: false)
          assert_library_placement_capability!
          RecordingStudioAttachable::Services::ResolvePlacements.call(
            parent_recording: self,
            include_trashed_images: include_trashed_images
          ).value
        end

        def reorder_library_placements!(**options)
          assert_library_placement_capability!
          RecordingStudioAttachable::Services::ReorderPlacements.call(parent_recording: self, **options).value
        end

        def remove_library_placement(**options)
          assert_library_placement_capability!
          RecordingStudioAttachable::Services::RemovePlacement.call(parent_recording: self, **options).value
        end

        private

        def assert_library_placement_capability!
          return unless respond_to?(:assert_capability!, true)

          assert_capability!(:library_placement, for_type: recordable_type)
        end
      end
    end
  end
end
