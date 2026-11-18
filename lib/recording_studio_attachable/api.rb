# frozen_string_literal: true

require_relative "api/attachment_actions"
require_relative "api/openapi_overrides"

module RecordingStudioAttachable
  module Api
    module_function

    def override_openapi(type:, action:, title: nil, summary: nil, description: nil)
      OpenapiOverrides.assign(type: type, action: action, title: title, summary: summary, description: description)
    end

    def openapi_for(type:, action:)
      OpenapiOverrides.for(type: type, action: action)
    end

    def install_configuration_error!
      return unless defined?(::RecordingStudioApi::ApiController)

      controller = ::RecordingStudioApi::ApiController
      name = "RecordingStudioAttachable::ConfigurationError"
      return if controller.rescue_handlers.any? { |registered, _handler| registered == name }

      controller.rescue_from(RecordingStudioAttachable::ConfigurationError) do |error|
        render_error(code: "configuration_error", message: error.message, status: :unprocessable_entity)
      end
    end

    def register!(apis: [:public])
      return unless defined?(::RecordingStudioApi)

      install_configuration_error!
      Array(apis).each { |api| AttachmentActions.register!(api) }
    end

    def role_for(action)
      roles = RecordingStudioAttachable.configuration.auth_roles
      key = action.to_sym == :import_attachment && roles.key?(:import) ? :import : :upload
      RecordingStudioAttachable.configuration.auth_role_for(key)
    end
  end
end
