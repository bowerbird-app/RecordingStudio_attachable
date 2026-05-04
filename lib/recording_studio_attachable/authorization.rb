# frozen_string_literal: true

module RecordingStudioAttachable
  module Authorization
    class NotAuthorizedError < RecordingStudioAttachable::Error; end

    class << self
      def authorize!(action:, actor:, recording:, capability_options: nil)
        return true if allowed?(action: action, actor: actor, recording: recording, capability_options: capability_options)

        raise NotAuthorizedError, "Not authorized to #{action} attachments for #{recording&.recordable_type || recording.class.name}"
      end

      def allowed?(action:, actor:, recording:, capability_options: nil)
        role = required_role_for(action, capability_options: capability_options)
        return false if role.blank?

        adapter = capability_options.to_h[:authorize_with] || RecordingStudioAttachable.configuration.authorize_with
        if adapter.respond_to?(:call)
          !!adapter.call(action: action, actor: actor, recording: recording, role: role)
        elsif defined?(RecordingStudioAccessible::Authorization)
          RecordingStudioAccessible::Authorization.allowed?(actor: actor, recording: recording, role: role)
        else
          false
        end
      end

      def required_role_for(action, capability_options: nil)
        roles = RecordingStudioAttachable.configuration.auth_roles.merge(capability_options.to_h[:auth_roles].to_h)
        RecordingStudioAttachable.configuration.normalize_role(roles[action.to_sym])
      end
    end
  end
end
