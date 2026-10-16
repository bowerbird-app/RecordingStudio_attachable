# frozen_string_literal: true

module RecordingStudioAttachable
  module Api
    module AttachmentActions
      module_function

      def register!(api)
        register(api, :create_upload, CreateUpload, create_upload_contract, "Create a direct upload")
        register(api, :attach, Attach, attach_contract, "Attach uploaded files")
        register(api, :import_attachment, ImportAttachment, import_contract, "Import a file from a URL")
      end

      class CreateUpload
        def self.call(context)
          Errors.wrap { new(context).ticket }
        end

        def initialize(context)
          @context = context
          @params = context.params
        end

        def ticket
          reject_type!
          reject_size!
          direct_upload(reserve(create_blob))
        end

        private

        attr_reader :context, :params

        def reject_type!
          return if Limits.allowed?(recording, params[:content_type])

          Errors.invalid!("Content type #{params[:content_type]} is not allowed")
        end

        def reject_size!
          Errors.invalid!("byte_size must be zero or more") if params[:byte_size].to_i.negative?
          return if Limits.size_allowed?(recording, params[:byte_size])

          Errors.invalid!("File exceeds maximum file size")
        end

        def create_blob
          ActiveStorage::Blob.create_before_direct_upload!(**blob_attributes)
        end

        def blob_attributes
          params.slice(:filename, :byte_size, :checksum, :content_type)
        end

        def reserve(blob)
          incoming = StorageLimit::IncomingBytes.for(root_recording, [blob])
          StorageLimit.with_storage_capacity!(root_recording, incoming) { blob }
        rescue StandardError
          drop(blob)
          raise
        end

        def drop(blob)
          return unless blob.respond_to?(:persisted?) && blob.persisted?

          StorageLimit.discard_unattached!([blob])
        rescue StandardError
          nil
        end

        def direct_upload(blob)
          ttl = ActiveStorage.service_urls_expire_in
          {
            signed_blob_id: blob.signed_id(expires_in: ttl),
            upload: upload_instructions(blob, ttl),
            expires_at: ttl.from_now.iso8601
          }
        end

        def upload_instructions(blob, ttl)
          {
            url: blob.service_url_for_direct_upload(expires_in: ttl),
            headers: blob.service_headers_for_direct_upload
          }
        end

        def recording
          context.recording
        end

        def root_recording
          recording.respond_to?(:root_recording) ? recording.root_recording || recording : recording
        end
      end

      class Attach
        def self.call(context)
          Errors.wrap { new(context).call }
        end

        def initialize(context)
          @context = context
          @params = context.params
        end

        def call
          Errors.invalid!("signed_blob_id or attachments is required") if missing?
          Errors.invalid!("Send signed_blob_id or attachments, not both") if mixed?
          batch? ? many : one
        end

        private

        attr_reader :context, :params

        def missing?
          params[:signed_blob_id].blank? && !batch?
        end

        def mixed?
          params[:signed_blob_id].present? && batch?
        end

        def batch?
          params.key?(:attachments)
        end

        def one
          Payload.one(Errors.finish!(Services::RecordAttachmentUpload.call(**single_arguments)))
        end

        def many
          Payload.many(Errors.finish!(Services::RecordAttachmentUploads.call(**batch_arguments)))
        end

        def single_arguments
          shared.merge(signed_blob_id: params[:signed_blob_id], **presentation(params))
        end

        def batch_arguments
          shared.merge(attachments: items)
        end

        def shared
          { parent_recording: context.recording, actor: context.actor }
        end

        def items
          Array(params[:attachments]).map { |item| item_arguments(item) }
        end

        def item_arguments(item)
          Errors.invalid!("Each attachment needs signed_blob_id") unless item.is_a?(Hash)
          { signed_blob_id: item[:signed_blob_id], **presentation(item) }
        end

        def presentation(source)
          source.slice(:name, :description, :caption, :credit, :alt_text)
        end
      end

      class ImportAttachment
        def self.call(context)
          Errors.wrap { new(context).call }
        end

        def initialize(context)
          @context = context
          @params = context.params
          @fetched = nil
        end

        def call
          @fetched = fetch
          Payload.one(Errors.finish!(record))
        ensure
          SafeRemoteFetch.close_io(@fetched&.io)
        end

        private

        attr_reader :context, :params, :fetched

        def fetch
          SafeRemoteFetch.call(remote_file, max_bytes: Limits.max_file_size(context.recording))
        end

        def record
          Services::ImportAttachment.call(**import_arguments)
        end

        def import_arguments
          {
            parent_recording: context.recording,
            io: fetched.io,
            filename: filename,
            content_type: fetched.content_type.presence || "application/octet-stream",
            actor: context.actor,
            name: params[:name],
            description: params[:description],
            source: "api_import"
          }
        end

        def remote_file
          RemoteFile.new(
            uri: parsed_url,
            filename: filename,
            content_type: "application/octet-stream",
            allowed_hosts: RecordingStudioAttachable.configuration.import_allowed_hosts,
            name: params[:name],
            description: params[:description]
          )
        end

        def parsed_url
          URI.parse(params[:url].to_s)
        rescue URI::InvalidURIError => e
          Errors.invalid!(e)
        end

        def filename
          File.basename(parsed_url.path.presence || "download")
        end
      end

      module Errors
        module_function

        def wrap
          yield
        rescue RecordingStudioAttachable::StorageLimitError,
               RecordingStudioAttachable::StorageLimitUnknown,
               RecordingStudioAttachable::SafeRemoteFetch::Error,
               ActiveRecord::RecordInvalid,
               URI::InvalidURIError => e
          invalid!(e)
        rescue StandardError => e
          raise e unless plan_limit?(e)

          invalid!(e)
        end

        def finish!(result)
          return result.value if result.success?
          raise ::RecordingStudioApi::AuthorizationError, result.error if denied?(result.error)

          invalid!(result.error, details: result.errors)
        end

        def invalid!(error, details: [])
          message = error.respond_to?(:message) ? error.message : error.to_s
          raise ::RecordingStudioApi::InvalidActionInputError.new(message, details: details)
        end

        def denied?(message)
          message.to_s.start_with?("Not authorized")
        end

        def plan_limit?(error)
          defined?(::RecordingStudioStripe::PlanLimitReached) && error.is_a?(::RecordingStudioStripe::PlanLimitReached)
        end
      end

      module Limits
        module_function

        def allowed?(recording, content_type)
          configuration.allowed_content_type?(content_type, allowed_content_types: option(recording, :allowed_content_types))
        end

        def size_allowed?(recording, byte_size)
          size = byte_size.to_i
          return false if size.negative?

          max = max_file_size(recording)
          max.blank? || size <= max
        end

        def max_file_size(recording)
          option(recording, :max_file_size)
        end

        def option(recording, name)
          capability_options(recording).fetch(name) { configuration.public_send(name) }
        end

        def capability_options(recording)
          return {} unless defined?(RecordingStudio) && RecordingStudio.respond_to?(:capability_options)

          RecordingStudio.capability_options(:attachable, for_type: recording.recordable_type) || {}
        end

        def configuration
          RecordingStudioAttachable.configuration
        end
      end

      module Payload
        module_function

        def one(recording)
          attachment = recording.recordable
          {
            id: recording.id,
            kind: attachment.attachment_kind,
            name: attachment.name,
            urls: { file: file_url(recording, attachment) }
          }
        end

        def many(recordings)
          { attachments: Array(recordings).map { |recording| one(recording) } }
        end

        def file_url(recording, attachment)
          attachment.original_url(rails_url: file_path(recording))
        end

        def file_path(recording)
          RecordingStudioAttachable::Engine.routes.url_helpers.attachment_file_path(recording)
        end
      end

      class << self
        private

        def register(api, name, handler, contract, summary)
          return if ::RecordingStudioApi.capability_action(name, api: api)

          ::RecordingStudioApi.register_capability_action(
            name,
            capability: :attachable, scope: :member, http_verb: :post, version: "1.0.0",
            required_role: Api.role_for(name), handler: handler, serializer: method(:serialize),
            input_contract: contract, openapi: { summary: summary }, api: api
          )
        end

        def serialize(result)
          result
        end

        def create_upload_contract
          fields = {
            filename: { type: :string, required: true, allow_blank: false },
            byte_size: { type: :integer, required: true },
            checksum: { type: :string, required: true, allow_blank: false },
            content_type: { type: :string, required: true, allow_blank: false }
          }
          { reject_unknown: false, fields: fields }
        end

        def attach_contract
          fields = {
            signed_blob_id: { type: :string, required: false, allow_blank: true },
            name: optional_string,
            description: optional_string,
            caption: optional_string,
            credit: optional_string,
            alt_text: optional_string,
            attachments: { type: :array, required: false }
          }
          { reject_unknown: false, fields: fields }
        end

        def import_contract
          fields = {
            url: { type: :string, required: true, allow_blank: false },
            name: optional_string,
            description: optional_string
          }
          { reject_unknown: false, fields: fields }
        end

        def optional_string
          { type: :string, required: false, allow_blank: true }
        end
      end
    end
  end
end
