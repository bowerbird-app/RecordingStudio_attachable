# frozen_string_literal: true

require_relative "authorization/trash_visibility"
require_relative "authorization/owner_availability"

module RecordingStudioAttachable
  module Authorization
    class NotAuthorizedError < RecordingStudioAttachable::Error; end
    class CapabilityNotEnabledError < NotAuthorizedError; end
    class OwnerUnavailableError < NotAuthorizedError; end

    READ_ACTIONS = %i[view download].freeze

    class << self
      def authorize!(action:, actor:, recording:, capability_options: nil)
        assert_attachable_enabled!(recording: recording, capability_options: capability_options)
        raise OwnerUnavailableError, denial_message(action, recording) unless visible_to?(
          recording, actor: actor, action: action
        )
        raise NotAuthorizedError, denial_message(action, recording) unless role_allowed?(
          action: action, actor: actor, recording: recording, capability_options: capability_options
        )
        return true if owner_available?(action: action, actor: actor, recording: recording)

        raise OwnerUnavailableError, denial_message(action, recording)
      end

      def allowed?(action:, actor:, recording:, capability_options: nil)
        return false unless attachable_enabled?(recording: recording, capability_options: capability_options)
        return false unless visible_to?(recording, actor: actor, action: action)
        return false unless role_allowed?(
          action: action, actor: actor, recording: recording, capability_options: capability_options
        )

        owner_available?(action: action, actor: actor, recording: recording)
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

      def visible_to?(recording, actor:, action:)
        return true unless READ_ACTIONS.include?(action.to_sym)
        return true unless TrashVisibility.hidden?(recording)

        admin_on_parent?(actor, recording)
      end

      private

      def role_allowed?(action:, actor:, recording:, capability_options: nil)
        holds_role?(
          actor: actor,
          recording: recording,
          role: required_role_for(action, capability_options: capability_options),
          capability_options: capability_options,
          action: action
        )
      end

      def holds_role?(actor:, recording:, role:, capability_options: nil, action: :view)
        return false if role.blank?

        adapter = authorization_adapter(capability_options)
        return !!adapter.call(action: action, actor: actor, recording: recording, role: role) if adapter.respond_to?(:call)
        return false unless defined?(RecordingStudioAccessible::Authorization)

        RecordingStudioAccessible::Authorization.allowed?(actor: actor, recording: recording, role: role)
      end

      def admin_on_parent?(actor, recording)
        parent = owner_recording_for(recording)
        return false if actor.blank? || parent.blank?

        holds_role?(actor: actor, recording: parent, role: :admin, action: :view)
      end

      def owner_available?(action:, actor:, recording:)
        OwnerAvailability.allowed?(action: action, actor: actor, recording: recording)
      end

      def denial_message(action, recording)
        "Not authorized to #{action} attachments for #{recording&.recordable_type || recording.class.name}"
      end
    end
  end
end
