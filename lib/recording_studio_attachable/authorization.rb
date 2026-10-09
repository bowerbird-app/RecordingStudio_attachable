# frozen_string_literal: true

require_relative "library_authorization"

module RecordingStudioAttachable
  module Authorization
    class NotAuthorizedError < RecordingStudioAttachable::Error; end
    class CapabilityNotEnabledError < NotAuthorizedError; end

    class << self
      include LibraryAuthorization

      def authorize!(action:, actor:, recording:, capability_options: nil)
        assert_attachable_enabled!(recording: recording, capability_options: capability_options)
        return true if allowed?(action: action, actor: actor, recording: recording, capability_options: capability_options)

        raise NotAuthorizedError, "Not authorized to #{action} attachments for #{recording&.recordable_type || recording.class.name}"
      end

      def allowed?(action:, actor:, recording:, capability_options: nil)
        return false unless attachable_enabled?(recording: recording, capability_options: capability_options)

        role = required_role_for(action, capability_options: capability_options)
        return false if role.blank?

        adapter = authorization_adapter(capability_options)
        return !!adapter.call(action: action, actor: actor, recording: recording, role: role) if adapter.respond_to?(:call)

        return false unless defined?(RecordingStudioAccessible::Authorization)

        RecordingStudioAccessible::Authorization.allowed?(actor: actor, recording: recording, role: role)
      end

      def authorization_adapter(capability_options)
        capability_options.to_h[:authorize_with] || RecordingStudioAttachable.configuration.authorize_with
      end

      def required_role_for(action, capability_options: nil)
        roles = RecordingStudioAttachable.configuration.auth_roles.merge(capability_options.to_h[:auth_roles].to_h)
        RecordingStudioAttachable.configuration.normalize_role(roles[action.to_sym])
      end

      def attachable_enabled?(recording:, capability_options: nil)
        owner_type = owner_type_for(recording)
        return false if owner_type.blank?

        if defined?(RecordingStudio) &&
           RecordingStudio.respond_to?(:configuration) &&
           RecordingStudio.configuration.respond_to?(:capability_enabled?)
          RecordingStudio.configuration.capability_enabled?(:attachable, for_type: owner_type)
        else
          capability_options.present?
        end
      end

      def assert_attachable_enabled!(recording:, capability_options: nil)
        return if attachable_enabled?(recording: recording, capability_options: capability_options)

        raise CapabilityNotEnabledError, "Attachable capability is not enabled for #{owner_type_for(recording) || recording.class.name}"
      end

      def owner_recording_for(recording)
        return recording unless recording.respond_to?(:recordable_type)
        return recording.parent_recording if recording.recordable_type == "RecordingStudioAttachable::Attachment"

        recording
      end

      def owner_type_for(recording)
        owner_recording_for(recording)&.recordable_type
      end

      def authorize_placement!(action:, actor:, recording:)
        assert_placement_enabled!(recording: recording)
        return true if placement_allowed?(action: action, actor: actor, recording: recording)

        raise NotAuthorizedError, "Not authorized to #{action} photos for #{recording&.recordable_type || recording.class.name}"
      end

      def placement_allowed?(action:, actor:, recording:)
        return false unless placement_enabled?(recording: recording)

        role = required_role_for(action)
        return false if role.blank?

        adapter = authorization_adapter({})
        return !!adapter.call(action: action, actor: actor, recording: recording, role: role) if adapter.respond_to?(:call)

        return false unless defined?(RecordingStudioAccessible::Authorization)

        RecordingStudioAccessible::Authorization.allowed?(actor: actor, recording: recording, role: role)
      end

      def placement_enabled?(recording:)
        type = recording.respond_to?(:recordable_type) ? recording.recordable_type : nil
        return false if type.blank? || !defined?(RecordingStudio)

        if RecordingStudio.respond_to?(:configuration) && RecordingStudio.configuration.respond_to?(:capability_enabled?)
          RecordingStudio.configuration.capability_enabled?(:library_placement, for_type: type)
        else
          RecordingStudio.respond_to?(:capability_enabled?) &&
            RecordingStudio.capability_enabled?(:library_placement, for: type)
        end
      end

      def assert_placement_enabled!(recording:)
        return if placement_enabled?(recording: recording)

        raise CapabilityNotEnabledError, "Library placement is not enabled for #{recording&.recordable_type || recording.class.name}"
      end
    end
  end
end
