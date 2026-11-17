# frozen_string_literal: true

module RecordingStudioAttachable
  module Authorization
    class NotAuthorizedError < RecordingStudioAttachable::Error; end
    class CapabilityNotEnabledError < NotAuthorizedError; end
    class OwnerUnavailableError < NotAuthorizedError; end

    class << self
      def authorize!(action:, actor:, recording:, capability_options: nil)
        assert_attachable_enabled!(recording: recording, capability_options: capability_options)
        raise NotAuthorizedError, denial_message(action, recording) unless role_allowed?(
          action: action, actor: actor, recording: recording, capability_options: capability_options
        )
        return true if owner_available?(action: action, actor: actor, recording: recording)

        raise OwnerUnavailableError, denial_message(action, recording)
      end

      def allowed?(action:, actor:, recording:, capability_options: nil)
        return false unless attachable_enabled?(recording: recording, capability_options: capability_options)
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

      private

      def role_allowed?(action:, actor:, recording:, capability_options: nil)
        role = required_role_for(action, capability_options: capability_options)
        return false if role.blank?

        adapter = authorization_adapter(capability_options)
        return !!adapter.call(action: action, actor: actor, recording: recording, role: role) if adapter.respond_to?(:call)
        return false unless defined?(RecordingStudioAccessible::Authorization)

        RecordingStudioAccessible::Authorization.allowed?(actor: actor, recording: recording, role: role)
      end

      def owner_available?(action:, actor:, recording:)
        owner = owner_recording_for(recording)
        recordable_class = owner_recordable_class(owner)
        return true unless recordable_class.is_a?(Module)
        return availability_allowed?(owner, action, actor) if recordable_class.public_method_defined?(:attachable_available_for?)
        return false if availability_method_hidden?(recordable_class)

        true
      end

      # Only boolean true. false, nil, and any other object refuse.
      def availability_allowed?(owner, action, actor)
        result = owner.recordable.attachable_available_for?(actor: actor, action: action, recording: owner)
        result.equal?(true)
      rescue StandardError => e
        log_availability_error(e)
        false
      end

      def availability_method_hidden?(recordable_class)
        recordable_class.private_method_defined?(:attachable_available_for?) ||
          recordable_class.protected_method_defined?(:attachable_available_for?)
      end

      def owner_recordable_class(owner)
        return unless owner.respond_to?(:recordable_type)

        name = owner.recordable_type.to_s
        return if name.blank?

        name.safe_constantize
      end

      def log_availability_error(error)
        line = "RecordingStudioAttachable owner availability check failed (#{error.class})"
        if defined?(Rails) && Rails.respond_to?(:logger) && Rails.logger
          Rails.logger.warn(line)
        else
          warn(line)
        end
      end

      def denial_message(action, recording)
        "Not authorized to #{action} attachments for #{recording&.recordable_type || recording.class.name}"
      end
    end
  end
end
