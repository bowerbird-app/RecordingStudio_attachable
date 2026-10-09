# frozen_string_literal: true

module RecordingStudio
  module Capabilities
    module ImageLibrary
      def self.to(**options)
        RecordingStudio::Capabilities.include_for(:image_library, **options)
      end

      module RecordingMethods
        include RecordingStudio::Capability if defined?(RecordingStudio::Capability)

        def image_library(key: :default, actor: nil)
          assert_image_library_capability!
          RecordingStudioAttachable.library_for(self, key: key, actor: actor)
        end

        def image_libraries
          assert_image_library_capability!
          RecordingStudioAttachable.libraries_for(self)
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
