# frozen_string_literal: true

module RecordingStudioAttachable
  module LibraryAuthorization
    def authorize_library!(action:, actor:, recording:)
      assert_library_enabled!(recording: recording)
      return true if library_allowed?(action: action, actor: actor, recording: recording)

      owner_name = recording&.recordable_type || recording.class.name
      raise Authorization::NotAuthorizedError, "Not authorized to #{action} libraries for #{owner_name}"
    end

    def library_allowed?(action:, actor:, recording:)
      return false unless library_enabled?(recording: recording)

      role = required_role_for(action)
      return false if role.blank?

      adapter = authorization_adapter({})
      return !!adapter.call(action: action, actor: actor, recording: recording, role: role) if adapter.respond_to?(:call)

      return false unless defined?(RecordingStudioAccessible::Authorization)

      RecordingStudioAccessible::Authorization.allowed?(actor: actor, recording: recording, role: role)
    end

    def library_enabled?(recording:)
      owner = library_owner_for(recording)
      type = owner.respond_to?(:recordable_type) ? owner.recordable_type : nil
      return false if type.blank? || !defined?(RecordingStudio)

      if RecordingStudio.respond_to?(:configuration) && RecordingStudio.configuration.respond_to?(:capability_enabled?)
        RecordingStudio.configuration.capability_enabled?(:image_library, for_type: type)
      else
        RecordingStudio.respond_to?(:capability_enabled?) &&
          RecordingStudio.capability_enabled?(:image_library, for: type)
      end
    end

    def assert_library_enabled!(recording:)
      return if library_enabled?(recording: recording)

      owner_name = library_owner_for(recording)&.recordable_type || recording.class.name
      raise Authorization::CapabilityNotEnabledError, "Image library is not enabled for #{owner_name}"
    end

    def library_owner_for(recording)
      return recording.parent_recording if Placements.library_recording?(recording) && recording.respond_to?(:parent_recording)

      recording
    end
  end
end
