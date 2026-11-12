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
      RecordingStudioAttachable.configuration.auth_role_for(role_key(action.to_sym))
    end

    def role_key(action)
      roles = RecordingStudioAttachable.configuration.auth_roles
      return :import if action == :import_attachment && roles.key?(:import)
      return :revise if %i[revise_attachment replace_attachment].include?(action) && roles.key?(:revise)
      return :remove if action == :remove_attachment && roles.key?(:remove)

      :upload
    end
  end
end
