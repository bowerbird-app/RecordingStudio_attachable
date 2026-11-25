# frozen_string_literal: true

require_relative "api/attachment_actions"
require_relative "inline_bytes"
require_relative "mcp_copy/file_field"
require_relative "mcp_copy/text"

module RecordingStudioAttachable
  module McpCopy # rubocop:disable Metrics/ModuleLength
    ACTIONS = %i[create_upload attach import_attachment].freeze
    ID_INPUT = {
      description: "Recording id of the parent record."
    }.freeze
    FILE_PARAMS = ["file"].freeze
    FILE_PARAMS_KEY = "openai/fileParams"
    URL_FIELD = "A public https:// web address of a file already on the public web. " \
                "For a file the user attached in ChatGPT, send file. Never put a local path in url."
    FILENAME_FIELD = "File name to store, such as cover.jpg. Send it with data. A direct upload needs it too. " \
                     "Optional when you send url or file. When omitted on url, the name comes from the url path."

    module_function

    def upload_source_fields
      {
        "url" => { "type" => "string", "description" => URL_FIELD },
        "data" => { "type" => "string", "description" => data_field },
        "filename" => { "type" => "string", "description" => FILENAME_FIELD }
      }
    end

    def upload_file_field
      FileField.schema
    end

    def rights_confirmed_field
      UploadRights.field
    end

    def data_field
      limit = InlineBytes.size_words(RecordingStudioAttachable.configuration.inline_upload_max_bytes)
      "Base64 file bytes, or a base64 data URI. Send this with filename when the client can send the bytes. " \
        "Data uploads can be up to #{limit}. For a file attached in ChatGPT, send file. For a public web image, send url."
    end

    def register!
      return unless mcp_available?

      attachable_types.each { |type| register_type_tools(type) }
    end

    def tool_names(api: nil)
      return [] unless mcp_available?

      register!
      Names.list(attachable_types, api: api)
    end

    def tool_name(type, action)
      "#{type_token(type)}_#{action}"
    end

    def mcp_available?
      defined?(::RecordingStudioMcp) &&
        ::RecordingStudioMcp.respond_to?(:register_tool) &&
        ::RecordingStudioMcp.respond_to?(:tool_name)
    end

    def attachable_types
      configuration = RecordingStudio.configuration
      return [] unless configuration.respond_to?(:enabled_recordable_types_for)

      Array(configuration.enabled_recordable_types_for(:attachable)).map(&:to_s)
    end

    def type_token(type)
      helper = ::RecordingStudioMcp::ToolName
      return helper.type_singular_snake(type) if helper.respond_to?(:type_singular_snake)

      named = ::RecordingStudioMcp.tool_name(type, :show).to_s
      prefix = "show_"
      raise ArgumentError, "RecordingStudioMcp.tool_name did not return a show_ token for #{type}" unless named.start_with?(prefix)

      named.delete_prefix(prefix)
    end

    def register_type_tools(type)
      actions = Names.actions_for(type, nil)
      return if actions.empty?

      register_type_copy(type)
      actions.each { |action| register_action_tool(type, action) }
    end

    def register_type_copy(type)
      return unless ::RecordingStudioMcp.respond_to?(:register_type)
      return if type_described?(type)

      ::RecordingStudioMcp.register_type(type: type.to_s, description: Text.type_description(type))
    end

    def type_described?(type)
      return false unless ::RecordingStudioMcp.respond_to?(:configuration)

      existing = ::RecordingStudioMcp.configuration.type(type.to_s)
      existing.respond_to?(:description) && existing.description.to_s.strip != ""
    end

    def register_action_tool(type, action)
      spec = Api.openapi_for(type: type, action: action)
      ::RecordingStudioMcp.register_tool(
        name: tool_name(type, action),
        type: type.to_s,
        action: action,
        title: spec.fetch(:title),
        description: description_for(type, action),
        input: { "id" => ID_INPUT },
        output: spec.dig(:responses, "200", :description)
      )
    end

    def description_for(type, action)
      actions = Names.actions_for(type, nil)
      actions = [action] if actions.empty?
      names = actions.to_h { |item| [item, tool_name(type, item)] }
      Text.for(
        action,
        names: names,
        limits: Api::UploadRules.limits_paragraph(type),
        next_step: RecordingStudioAttachable.configuration.mcp_next_step_for(type)
      )
    end
    private_class_method :data_field, :mcp_available?, :attachable_types, :type_token,
                         :register_type_tools, :register_type_copy, :type_described?,
                         :register_action_tool, :description_for
  end
end

require_relative "mcp_copy/names"
