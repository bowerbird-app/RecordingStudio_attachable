# frozen_string_literal: true

require_relative "api/attachment_actions"

module RecordingStudioAttachable
  module McpCopy
    ACTIONS = %i[create_upload attach import_attachment].freeze
    OPENAPI = {
      create_upload: Api::AttachmentActions::CREATE_UPLOAD_OPENAPI,
      attach: Api::AttachmentActions::ATTACH_OPENAPI,
      import_attachment: Api::AttachmentActions::IMPORT_ATTACHMENT_OPENAPI
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
      spec = OPENAPI.fetch(action)
      ::RecordingStudioMcp.register_tool(
        name: action.to_s,
        action: action,
        title: spec.fetch(:title),
        description: spec.fetch(:description),
        input: PROTOCOL_INPUT,
        output: spec.dig(:responses, "200", :description)
      )
    end
    private_class_method :register_action_tool
  end
end
