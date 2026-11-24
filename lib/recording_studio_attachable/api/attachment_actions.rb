# frozen_string_literal: true

require_relative "attachment_contracts"

module RecordingStudioAttachable
  module Api
    module AttachmentActions
      module_function

      ATTACHMENT_ONE_SCHEMA = AttachmentContracts::ATTACHMENT_ONE_SCHEMA
      ATTACHMENT_MANY_SCHEMA = AttachmentContracts::ATTACHMENT_MANY_SCHEMA
      CREATE_UPLOAD_TICKET_SCHEMA = AttachmentContracts::CREATE_UPLOAD_TICKET_SCHEMA
      CREATE_UPLOAD_SUMMARY = AttachmentCopy::Text::CREATE_UPLOAD_SUMMARY
      CREATE_UPLOAD_COPY = AttachmentCopy::Text::CREATE_UPLOAD
      CREATE_UPLOAD_OPENAPI = {
        title: "Upload",
        summary: CREATE_UPLOAD_SUMMARY,
        description: CREATE_UPLOAD_COPY,
        responses: {
          "200" => {
            description: "Direct-upload ticket. Returns signed_blob_id, upload.url, upload.headers, " \
                         "and expires_at. This step does not attach the file.",
            content: {
              "application/json" => { schema: CREATE_UPLOAD_TICKET_SCHEMA }
            }
          }
        }
      }.freeze
      ATTACH_SUMMARY = AttachmentCopy::Text::ATTACH_SUMMARY
      ATTACH_COPY = AttachmentCopy::Text::ATTACH
      ATTACH_OPENAPI = {
        title: "Attach",
        summary: ATTACH_SUMMARY,
        description: ATTACH_COPY,
        responses: {
          "200" => {
            description: "One file returns id, kind, name, and urls.file. urls.file_url is the absolute URL " \
                         "when a public host is known. A list returns attachments, an array of those objects.",
            content: {
              "application/json" => {
                schema: { oneOf: [ATTACHMENT_ONE_SCHEMA, ATTACHMENT_MANY_SCHEMA] }
              }
            }
          }
        }
      }.freeze
      IMPORT_ATTACHMENT_SUMMARY = AttachmentCopy::Text::IMPORT_SUMMARY
      IMPORT_ATTACHMENT_COPY = AttachmentCopy::Text::IMPORT
      IMPORT_ATTACHMENT_OPENAPI = {
        title: "Import",
        summary: IMPORT_ATTACHMENT_SUMMARY,
        description: IMPORT_ATTACHMENT_COPY,
        responses: {
          "200" => {
            description: "The new attachment. Returns id, kind, name, and urls.file. urls.file_url is the " \
                         "absolute URL when a public host is known.",
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
          return server_ticket if server_source?

          DirectUpload.ticket(prepare)
        end

        private

        attr_reader :context, :params

        def server_source?
          params[:url].present? || params[:data].present?
        end

        def server_ticket
          raise ArgumentError, "Send url or data, not both" if params[:url].present? && params[:data].present?
          return fetch_ticket if params[:url].present?

          inline_ticket
        end

        def fetch_ticket
          RecordingStudioAttachable.fetch_upload(
            recording: context.recording,
            actor: context.actor,
            url: params[:url],
            filename: params[:filename]
          )
        end

        def inline_ticket
          RecordingStudioAttachable.inline_upload(
            recording: context.recording,
            actor: context.actor,
            data: params[:data],
            filename: params[:filename]
          )
        end

        def prepare
          require_direct_fields!
          DirectUpload.prepare!(
            recording: context.recording,
            actor: context.actor,
            filename: params[:filename],
            byte_size: params[:byte_size],
            checksum: params[:checksum],
            content_type: params[:content_type]
          )
        end

        def require_direct_fields!
          return if direct_fields_present?

          raise ArgumentError, "Send filename, byte_size, checksum, and content_type for a direct upload, " \
                               "or send url, or send data and filename."
        end

        def direct_fields_present?
          params[:filename].present? && !params[:byte_size].nil? &&
            params[:checksum].present? && params[:content_type].present?
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
          Payload.one(Errors.finish!(Services::RecordAttachmentUpload.call(**single_arguments)), actor: context.actor)
        end

        def many
          Payload.many(Errors.finish!(Services::RecordAttachmentUploads.call(**batch_arguments)), actor: context.actor)
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
          Payload.one(Errors.finish!(record), actor: context.actor)
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
        rescue RecordingStudioAttachable::Authorization::NotAuthorizedError => e
          raise ::RecordingStudioApi::AuthorizationError, e.message
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

        def one(recording, actor:)
          RecordingStudioAttachable.attachment_payload(recording, actor: actor)
        end

        def many(recordings, actor:)
          { attachments: Array(recordings).map { |recording| one(recording, actor: actor) } }
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
            input_contract: contract, openapi: openapi, api: api,
            openapi_for: ->(type:, action:) { Api.openapi_for(type: type, action: action) }
          )
        end

        def serialize(result)
          result
        end
      end
    end
  end
end
