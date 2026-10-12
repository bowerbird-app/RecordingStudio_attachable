# frozen_string_literal: true

module RecordingStudio
  module Capabilities
    module ImageLibrary
      ATTACHMENT_TYPE = "RecordingStudioAttachable::Attachment"

      def self.to(**options)
        compose(
          RecordingStudio::Capabilities::Library.to(**library_kwargs(options)),
          RecordingStudio::Capabilities.include_for(:image_library, **options.except(:types, :keys))
        )
      end

      def self.library_kwargs(options)
        kwargs = { types: Array(options[:types]).presence || [ATTACHMENT_TYPE] }
        kwargs[:keys] = options[:keys] if options[:keys].present?
        kwargs
      end
      private_class_method :library_kwargs

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
