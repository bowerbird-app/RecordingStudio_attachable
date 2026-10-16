# frozen_string_literal: true

return unless defined?(RecordingStudioApi)

RecordingStudio.enable_capability(:api_access_point, on: "Workspace")

RecordingStudioApi.configure do |config|
  config.documentation_enabled = true
  config.documentation_access = :public
  config.openapi_title = "Attachable API"
  config.rate_limit_oauth_enabled = false
  config.rate_limit_api_pre_auth_enabled = false
  config.rate_limit_api_enabled = false
  config.rate_limit_fail_closed = false
  config.api_management_authorization_required = false

  config.api :operations do |api|
    api.openapi_title = "Operations API"
    api.api_versions = %w[v1]
    api.default_access = :read_only
    api.api_management_authorization_required = false
  end
end

RecordingStudioApi.register_recordable_type_api(
  "Workspace",
  operations: %i[index show],
  serializer: ->(workspace, **) { { name: workspace.name } },
  output_keys: %i[name],
  capability_actions: %i[create_upload attach import_attachment]
)

RecordingStudioApi.register_recordable_type_api(
  "Page",
  operations: %i[index show],
  serializer: ->(page, **) { { title: page.title } },
  output_keys: %i[title]
)

RecordingStudioAttachable::Api.register!(apis: [:public, :operations])

RecordingStudio.enable_capability(:trashable, on: "RecordingStudioAttachable::Attachment") if defined?(RecordingStudioTrashable)
