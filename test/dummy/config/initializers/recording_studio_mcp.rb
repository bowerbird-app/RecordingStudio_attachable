# frozen_string_literal: true

return unless defined?(RecordingStudioMcp)

RecordingStudioMcp.configure do |config|
  config.mcp_mount_path = "/recording_studio_mcp"
  config.oauth_protected_resource_path = "/.well-known/oauth-protected-resource/recording_studio_mcp"
  config.oauth_engine_mount_path = "/recording_studio_oauth"
end

%w[Workspace Page].each do |type|
  RecordingStudioMcp.register_type(
    type: type,
    description: "#{type} records nest by parent_id. root_id is the workspace. Call describe before you write."
  )
end

attachable_tools_on = lambda do |api|
  RecordingStudio.configuration.enabled_recordable_types_for(:attachable).flat_map do |type|
    registration = RecordingStudioApi.recordable_registration_for(type.to_s, api: api)
    next [] unless registration

    RecordingStudioAttachable::McpCopy::ACTIONS.filter_map do |action|
      next unless registration.supports_capability_action?(action)

      RecordingStudioAttachable::McpCopy.tool_name(type, action)
    end
  end
end

include_attachable_mcp = lambda do |*|
  RecordingStudioMcp.register_server(:public, api: :public) do
    include_tools(:list, :show, *attachable_tools_on.call(:public))
  end
  RecordingStudioMcp.register_server(:operations, api: :operations, allow_sensitive: true) do
    include_tools(*attachable_tools_on.call(:operations))
  end
end

Rails.application.config.to_prepare(&include_attachable_mcp)
