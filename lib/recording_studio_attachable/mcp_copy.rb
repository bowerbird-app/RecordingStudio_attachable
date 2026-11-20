# frozen_string_literal: true

require_relative "api/attachment_copy"

module RecordingStudioAttachable
  module McpCopy
    ACTIONS = %i[create_upload attach import_attachment].freeze
    TITLES = {
      create_upload: "Upload",
      attach: "Attach",
      import_attachment: "Import"
    }.freeze
    DESCRIPTIONS = {
      create_upload: Api::AttachmentCopy::Text::CREATE_UPLOAD,
      attach: Api::AttachmentCopy::Text::ATTACH,
      import_attachment: Api::AttachmentCopy::Text::IMPORT
    }.freeze
    OUTPUTS = {
      create_upload: "Direct-upload ticket with signed_blob_id, upload.url, upload.headers, and expires_at.",
      attach: "One file returns id, kind, name, and urls.file. A list returns attachments, an array of those objects.",
      import_attachment: "The new attachment with id, kind, name, and urls.file."
    }.freeze
    TYPE_INPUT = {
      description: Api::AttachmentCopy::Fields::TYPE.fetch(:description)
    }.freeze
    ID_INPUT = {
      description: "Recording id of the parent record."
    }.freeze
    PROTOCOL_INPUT = {
      "type" => TYPE_INPUT,
      "id" => ID_INPUT
    }.freeze
    FIELD_SETS = {
      create_upload: Api::AttachmentCopy::Fields::CREATE_UPLOAD,
      attach: Api::AttachmentCopy::Fields::ATTACH,
      import_attachment: Api::AttachmentCopy::Fields::IMPORT
    }.freeze

    module_function

    def register!
      return unless defined?(::RecordingStudioMcp)
      return unless ::RecordingStudioMcp.respond_to?(:register_tool)

      ACTIONS.each { |action| register_action_tool(action) }
    end

    def tool_names
      ACTIONS.map(&:to_s)
    end

    def register_action_tool(action)
      # MCP 0.44 treats a missing type as a generic tree tool and skips the API
      # action lookup, so tools/list would only advertise id. A blank type keeps
      # the action contract. The dispatcher still reads args["type"].
      options = {
        name: action.to_s,
        action: action,
        title: TITLES.fetch(action),
        description: DESCRIPTIONS.fetch(action),
        input: input_for(action),
        output: OUTPUTS.fetch(action)
      }
      options[:type] = ""
      ::RecordingStudioMcp.register_tool(**options)
    end

    def input_for(action)
      PROTOCOL_INPUT.merge(field_input(FIELD_SETS.fetch(action)))
    end

    def field_input(fields)
      fields.to_h do |name, meta|
        [name.to_s, { description: meta.fetch(:description) }]
      end
    end
    private_class_method :register_action_tool, :field_input
  end
end
