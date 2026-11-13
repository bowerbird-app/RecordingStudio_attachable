# frozen_string_literal: true

require_relative "attachment_contracts"

module RecordingStudioAttachable
  module Api
    module AttachmentActions
      module_function

      ATTACHMENT_ONE_SCHEMA = AttachmentContracts::ATTACHMENT_ONE_SCHEMA
      CREATE_UPLOAD_TICKET_SCHEMA = AttachmentContracts::CREATE_UPLOAD_TICKET_SCHEMA
      CREATE_UPLOAD_COPY =
        "An attachment is an uploaded file linked to a record, like a PDF, an image or a document. " \
        "Step 1 of 2. Step 2 is Attach, or Add File or Add Image for a press kit Files or Images " \
        "section. Use this when you have the file yourself. Send filename, byte_size, checksum and " \
        "content_type, and you get back an upload URL and a signed_blob_id. PUT the file to that " \
        "URL, then send the signed_blob_id to step 2. This step adds nothing to the record yet. " \
        "The parent record must already exist."
      CREATE_UPLOAD_OPENAPI = {
        title: "Upload",
        summary: CREATE_UPLOAD_COPY,
        description: CREATE_UPLOAD_COPY,
        responses: {
          "200" => {
            description: "A direct-upload ticket. This step does not attach the file.",
            content: {
              "application/json" => { schema: CREATE_UPLOAD_TICKET_SCHEMA }
            }
          }
        }
      }.freeze
      ATTACH_COPY =
        "An attachment is an uploaded file linked to a record, like a PDF, an image or a document. " \
        "Step 2 of 2. Step 1 is Upload: call Upload, PUT the file to its URL, then send the " \
        "signed_blob_id here. Links one signed_blob_id, or several in attachments, to this record " \
        "as plain attachments. For a press kit Files or Images section, use Add File or Add Image " \
        "instead, so the file shows up as an item in that section. The parent record must already exist."
      ATTACH_OPENAPI = {
        title: "Attach",
        summary: ATTACH_COPY,
        description: ATTACH_COPY
      }.freeze
      IMPORT_ATTACHMENT_COPY =
        "An attachment is an uploaded file linked to a record, like a PDF, an image or a document. " \
        "One step, no upload needed. Use this when the file is already online at a URL. " \
        "It downloads the file and attaches it to this record as a plain attachment in a single call, " \
        "so there's no Upload, PUT or signed_blob_id. For a press kit Files or Images section, use " \
        "Add File or Add Image instead, so the file shows up as an item in that section. " \
        "The parent record must already exist."
      IMPORT_ATTACHMENT_OPENAPI = {
        title: "Import",
        summary: IMPORT_ATTACHMENT_COPY,
        description: IMPORT_ATTACHMENT_COPY,
        responses: {
          "200" => {
            description: "The new attachment.",
            content: {
              "application/json" => { schema: ATTACHMENT_ONE_SCHEMA }
            }
          }
        }
      }.freeze

      def register!(api)
        register(api, :create_upload, CreateUpload, AttachmentContracts.create_upload, CREATE_UPLOAD_OPENAPI)
        register(api, :attach, Attach, AttachmentContracts.attach, ATTACH_OPENAPI)
        register(api, :import_attachment, ImportAttachment, AttachmentContracts.import_attachment, IMPORT_ATTACHMENT_OPENAPI)
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
          DirectUpload.ticket(prepare)
        end

        private

        attr_reader :context, :params

        def prepare
          DirectUpload.prepare!(
            recording: context.recording,
            actor: context.actor,
            filename: params[:filename],
            byte_size: params[:byte_size],
            checksum: params[:checksum],
            content_type: params[:content_type]
          )
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
        INPUT_ERRORS = [
          ArgumentError,
          RecordingStudioAttachable::StorageLimitError,
          RecordingStudioAttachable::StorageLimitUnknown,
          RecordingStudioAttachable::SafeRemoteFetch::Error,
          ActiveRecord::RecordInvalid,
          URI::InvalidURIError
        ].freeze

        module_function

        def wrap
          yield
        rescue *INPUT_ERRORS => e
          invalid!(e)
        rescue StandardError => e
          raise unless plan_limit?(e)

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

        def register(api, name, handler, contract, openapi)
          return if ::RecordingStudioApi.capability_action(name, api: api)

          ::RecordingStudioApi.register_capability_action(
            name,
            capability: :attachable, scope: :member, http_verb: :post, version: "1.0.0",
            required_role: Api.role_for(name), handler: handler, serializer: method(:serialize),
            input_contract: contract, openapi: openapi, api: api
          )
        end

        def serialize(result)
          result
        end
      end
    end
  end
end
