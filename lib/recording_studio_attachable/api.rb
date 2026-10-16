# frozen_string_literal: true

require_relative "api/attachment_actions"

module RecordingStudioAttachable
  module Api
    module_function

    def register!(apis: [:public])
      return unless defined?(::RecordingStudioApi)

      Array(apis).each { |api| AttachmentActions.register!(api) }
    end

    def role_for(action)
      roles = RecordingStudioAttachable.configuration.auth_roles
      key = action.to_sym == :import_attachment && roles.key?(:import) ? :import : :upload
      RecordingStudioAttachable.configuration.auth_role_for(key)
    end
  end
end
