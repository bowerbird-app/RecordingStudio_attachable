# frozen_string_literal: true

module RecordingStudio
  module Capabilities
    module LibraryPlacement
      ATTACHMENT_TYPE = "RecordingStudioAttachable::Attachment"

      def self.to(**options)
        compose(
          RecordingStudio::Capabilities::Placeable.to(**placeable_kwargs(options)),
          RecordingStudio::Capabilities.include_for(:library_placement, **options.except(:types, :libraries))
        )
      end

      def self.placeable_kwargs(options)
        kwargs = { types: Array(options[:types]).presence || [ATTACHMENT_TYPE] }
        kwargs[:libraries] = options[:libraries] if options[:libraries].present?
        kwargs
      end
      private_class_method :placeable_kwargs

      def self.compose(primary, extra)
        Module.new do
          define_singleton_method(:included) do |base|
            base.include primary
            base.include extra
          end
        end
      end
      private_class_method :compose

      module RecordingMethods
        include RecordingStudio::Capability if defined?(RecordingStudio::Capability)

        def place_library_image(attachment_recording:, actor: nil, **_ignored)
          assert_library_placement_capability!
          RecordingStudioAttachable.place_library_image(
            self,
            attachment_recording: attachment_recording,
            actor: actor
          )
        end

        def upload_to_library_and_place(**options)
          assert_library_placement_capability!
          RecordingStudioAttachable.upload_to_library_and_place(parent_recording: self, **options)
        end

        def library_placements(include_trashed_images: false, **options)
          assert_library_placement_capability!
          RecordingStudioAttachable::Placements.resolve(
            self,
            include_trashed_images: include_trashed_images,
            **options
          )
        end

        def reorder_library_placements!(ordered_recording_ids: nil, actor: nil, **options)
          assert_library_placement_capability!
          RecordingStudioAttachable.reorder_library_placements!(
            self,
            ordered_recording_ids: ordered_recording_ids || options[:ids],
            actor: actor,
            **options.except(:ids)
          )
        end

        def remove_library_placement(placement_recording:, actor: nil, **_ignored)
          assert_library_placement_capability!
          RecordingStudioAttachable.remove_library_placement(
            self,
            placement_recording: placement_recording,
            actor: actor
          )
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
