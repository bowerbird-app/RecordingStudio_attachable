# frozen_string_literal: true

require_relative "api/attachment_actions"
require_relative "mcp_copy/text"

module RecordingStudioAttachable
  module McpCopy
    ACTIONS = %i[create_upload attach import_attachment].freeze
    ID_INPUT = {
      description: "Recording id of the parent record."
    }.freeze

    module_function

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

    def names_for(type)
      ACTIONS.map { |action| tool_name(type, action) }
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
      register_type_copy(type)
      ACTIONS.each { |action| register_action_tool(type, action) }
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
      upload, attach, import = names_for(type)
      Text.for(action, upload: upload, attach: attach, import: import, limits: Api::UploadRules.limits_paragraph(type))
    end
    private_class_method :names_for, :mcp_available?, :attachable_types, :type_token,
                         :register_type_tools, :register_type_copy, :type_described?,
                         :register_action_tool, :description_for
  end
end

require_relative "mcp_copy/names"
