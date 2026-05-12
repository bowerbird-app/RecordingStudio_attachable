# frozen_string_literal: true

module RecordingStudio
  module Capabilities
    module Attachable
      def self.to(**options)
        Module.new do
          extend ActiveSupport::Concern

          included do |base|
            next unless defined?(RecordingStudio)

            RecordingStudio.enable_capability(:attachable, on: base.name)
            RecordingStudio.set_capability_options(:attachable, on: base.name, **options)
            RecordingStudio.register_recordable_type("RecordingStudioAttachable::Attachment")
          end
        end
      end

      module RecordingMethods
        include RecordingStudio::Capability if defined?(RecordingStudio::Capability)

        def attachments(**options)
          assert_attachable_capability!
          RecordingStudioAttachable::Queries::ForRecording.new(
            recording: self,
            **options
          ).call
        end

        def images(scope: nil, include_trashed: false, search: nil, page: nil, per_page: nil)
          attachments(scope: scope, kind: :images, include_trashed: include_trashed, search: search, page: page,
                      per_page: per_page)
        end

        def files(scope: nil, include_trashed: false, search: nil, page: nil, per_page: nil)
          attachments(scope: scope, kind: :files, include_trashed: include_trashed, search: search, page: page,
                      per_page: per_page)
        end

        def has_attachments?(scope: nil, kind: nil, include_trashed: false)
          attachments(scope: scope, kind: kind, include_trashed: include_trashed).exists?
        end

        def record_attachment_upload(**options)
          assert_attachable_capability!
          RecordingStudioAttachable::Services::RecordAttachmentUpload.call(parent_recording: self, **options).value
        end

        def record_attachment_uploads(**options)
          assert_attachable_capability!
          RecordingStudioAttachable::Services::RecordAttachmentUploads.call(parent_recording: self, **options).value
        end

        def import_attachment(**options)
          assert_attachable_capability!
          RecordingStudioAttachable::Services::ImportAttachment.call(parent_recording: self, **options).value
        end

        def import_attachments(**options)
          assert_attachable_capability!
          RecordingStudioAttachable::Services::ImportAttachments.call(parent_recording: self, **options).value
        end

        def revise_attachment_metadata(**options)
          assert_attachment_recording!
          RecordingStudioAttachable::Services::ReviseAttachmentMetadata.call(attachment_recording: self, **options).value
        end

        def replace_attachment_file(**options)
          assert_attachment_recording!
          RecordingStudioAttachable::Services::ReplaceAttachmentFile.call(attachment_recording: self, **options).value
        end

        def remove_attachment(**options)
          assert_attachment_recording!
          RecordingStudioAttachable::Services::RemoveAttachment.call(attachment_recording: self, **options).value
        end

        def remove_attachments(**options)
          assert_attachable_capability!
          RecordingStudioAttachable::Services::RemoveAttachments.call(parent_recording: self, **options).value
        end

        def restore_attachment(**options)
          assert_attachment_recording!
          RecordingStudioAttachable::Services::RestoreAttachment.call(attachment_recording: self, **options).value
        end

        private

        def assert_attachable_capability!
          return unless respond_to?(:assert_capability!, true)

          assert_capability!(:attachable, for_type: attachable_owner_type)
        end

        def assert_attachment_recording!
          raise ArgumentError, "Recording is not an attachment" unless recordable_type == "RecordingStudioAttachable::Attachment"
        end

        def attachable_owner_type
          recordable_type == "RecordingStudioAttachable::Attachment" ? parent_recording&.recordable_type : recordable_type
        end
      end
    end
  end
end
