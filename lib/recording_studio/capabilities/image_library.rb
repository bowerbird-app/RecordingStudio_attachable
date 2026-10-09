# frozen_string_literal: true

module RecordingStudio
  module Capabilities
    module ImageLibrary
      def self.to(**options)
        RecordingStudio::Capabilities.include_for(:image_library, **options)
      end

      module RecordingMethods
        include RecordingStudio::Capability if defined?(RecordingStudio::Capability)

        def image_library(actor: nil)
          assert_image_library_capability!
          RecordingStudioAttachable.library_for(self, actor: actor)
        end

        def default_library(actor: nil)
          image_library(actor: actor)
        end

        def image_libraries
          assert_image_library_capability!
          RecordingStudioAttachable.libraries_for(self)
        end

        def create_image_library(name:, description: nil, actor: nil)
          assert_image_library_capability!
          RecordingStudioAttachable.create_library(self, name: name, description: description, actor: actor)
        end

        def rename_image_library(library_recording, name:, description: :keep, actor: nil)
          assert_image_library_capability!
          RecordingStudioAttachable.rename_library(
            library_recording,
            name: name,
            description: description,
            actor: actor
          )
        end

        def trash_image_library(library_recording, actor: nil, impersonator: nil)
          assert_image_library_capability!
          RecordingStudioAttachable.trash_library(library_recording, actor: actor, impersonator: impersonator)
        end

        private

        def assert_image_library_capability!
          return unless respond_to?(:assert_capability!, true)

          assert_capability!(:image_library, for_type: recordable_type)
        end
      end
    end
  end
end
