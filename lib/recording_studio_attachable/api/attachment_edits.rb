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
          api_authorize(:revise_attachment)
          Payload.one(Member.finish_recording!(recording.revise_attachment_metadata(actor: context.actor, **fields)))
        end

        private

        attr_reader :context, :params

        def api_authorize(action)
          Member.api_authorize(context, action)
        end

        def recording
          Member.attachment_recording(context)
        end

        def fields
          params.slice(:name, :description, :caption, :credit, :alt_text)
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
          api_authorize(:replace_attachment)
          Payload.one(Member.finish_recording!(recording.replace_attachment_file(actor: context.actor, **fields)))
        end

        private

        attr_reader :context, :params

        def api_authorize(action)
          Member.api_authorize(context, action)
        end

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
          api_authorize(:remove_attachment)
          Payload.one(Member.finish_recording!(recording.remove_attachment(actor: context.actor)))
        end

        private

        attr_reader :context, :params

        def api_authorize(action)
          Member.api_authorize(context, action)
        end

        def recording
          Member.attachment_recording(context)
        end
      end

      module EditDocs
        module_function

        def revise_contract
          presentation = %i[name description caption credit alt_text].index_with { optional_string }
          { reject_unknown: false, fields: { attachment_recording_id: optional_string }.merge(presentation) }
        end

        def replace_contract
          {
            reject_unknown: false,
            fields: {
              attachment_recording_id: optional_string,
              signed_blob_id: { type: :string, required: true, allow_blank: false },
              name: optional_string,
              description: optional_string
            }
          }
        end

        def remove_contract
          {
            reject_unknown: false,
            fields: { attachment_recording_id: optional_string }
          }
        end

        def revise_openapi
          {
            title: "Attachment - Revise",
            summary: "Attachment - Revise",
            description: "Change the caption or alt text on this file."
          }
        end

        def replace_openapi
          {
            title: "Attachment - Replace",
            summary: "Attachment - Replace",
            description: "Swap this file for one you already uploaded."
          }
        end

        def remove_openapi
          {
            title: "Attachment - Remove",
            summary: "Attachment - Remove",
            description: "Take this file off the page."
          }
        end

        def optional_string
          { type: :string, required: false, allow_blank: true }
        end
      end

      module Member
        module_function

        def api_authorize(context, action)
          grant = context.access_grant
          raise ::RecordingStudioApi::AuthorizationError, "API access grant is not authorized for this capability" if grant.nil?

          grant.authorize!(recording: context.recording, role: Api.role_for(action))
        end

        def finish_recording!(recording)
          return recording if recording.present?

          Errors.invalid!("That attachment change did not finish")
        end

        def attachment_recording(context)
          recording = context.recording
          return recording if attachment?(recording)

          child = child_attachment(context)
          Errors.invalid!("Recording is not an attachment") unless attachment?(child)
          child
        end

        def attachment?(recording)
          recording&.recordable_type == "RecordingStudioAttachable::Attachment"
        end

        def child_attachment(context)
          id = context.params[:attachment_recording_id]
          Errors.invalid!("attachment_recording_id is required") if id.blank?
          return unless context.recording.respond_to?(:child_recordings)

          context.recording.child_recordings.find_by(id: id)
        end
      end
    end
  end
end
