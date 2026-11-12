# frozen_string_literal: true

module RecordingStudioAttachable
  module Api
    module AttachmentActions
      class ReviseAttachment
        def self.call(context)
          Errors.wrap { new(context).call }
        end

        def initialize(context)
          @context = context
          @params = context.params
        end

        def call
          result = Services::ReviseAttachmentMetadata.call(attachment_recording: recording, actor: context.actor, **fields)
          Payload.one(Errors.finish!(result))
        end

        private

        attr_reader :context, :params

        def recording
          Member.attachment_recording(context)
        end

        def fields
          Attach.new(context).presentation(params)
        end
      end

      class ReplaceAttachment
        def self.call(context)
          Errors.wrap { new(context).call }
        end

        def initialize(context)
          @context = context
          @params = context.params
        end

        def call
          result = Services::ReplaceAttachmentFile.call(attachment_recording: recording, actor: context.actor, **fields)
          Payload.one(Errors.finish!(result))
        end

        private

        attr_reader :context, :params

        def recording
          Member.attachment_recording(context)
        end

        def fields
          params.slice(:signed_blob_id, :name, :description)
        end
      end

      class RemoveAttachment
        def self.call(context)
          Errors.wrap { new(context).call }
        end

        def initialize(context)
          @context = context
          @params = context.params
        end

        def call
          result = Services::RemoveAttachment.call(attachment_recording: recording, actor: context.actor)
          Payload.one(Errors.finish!(result))
        end

        private

        attr_reader :context, :params

        def recording
          Member.attachment_recording(context)
        end
      end

      module EditDocs
        module_function

        def revise_contract
          presentation = %i[name description caption credit alt_text].index_with { AttachmentActions.optional_string }
          { reject_unknown: false, fields: { attachment_recording_id: AttachmentActions.optional_string }.merge(presentation) }
        end

        def replace_contract
          {
            reject_unknown: false,
            fields: {
              attachment_recording_id: AttachmentActions.optional_string,
              signed_blob_id: { type: :string, required: true, allow_blank: false },
              name: AttachmentActions.optional_string,
              description: AttachmentActions.optional_string
            }
          }
        end

        def remove_contract
          {
            reject_unknown: false,
            fields: { attachment_recording_id: AttachmentActions.optional_string }
          }
        end

        def revise_openapi
          {
            title: "Attachment - Revise",
            summary: "Change the caption or alt text on this file.",
            description: "Change the caption or alt text on this file."
          }
        end

        def replace_openapi
          {
            title: "Attachment - Replace",
            summary: "Swap this file for one you already uploaded.",
            description: "Swap this file for one you already uploaded."
          }
        end

        def remove_openapi
          {
            title: "Attachment - Remove",
            summary: "Take this file off the page.",
            description: "Take this file off the page."
          }
        end
      end

      module Member
        module_function

        def attachment_recording(context)
          id = context.params[:attachment_recording_id]
          Errors.invalid!("attachment_recording_id is required") if id.blank?

          context.recording.child_recordings.find_by(id: id)
        end
      end
    end
  end
end
