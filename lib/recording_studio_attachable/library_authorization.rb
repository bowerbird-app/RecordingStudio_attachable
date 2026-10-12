# frozen_string_literal: true

module RecordingStudioAttachable
  module LibraryAuthorization
    def authorize_library!(action:, actor:, recording:)
      wrap_library_authorization_errors do
        RecordingStudioLibrary::Authorization.authorize_library!(action: action, actor: actor, recording: recording)
      end
    end

    def library_allowed?(action:, actor:, recording:)
      RecordingStudioLibrary::Authorization.library_allowed?(action: action, actor: actor, recording: recording)
    end

    def library_enabled?(recording:)
      RecordingStudioLibrary::Authorization.library_enabled?(recording: recording)
    end

    def assert_library_enabled!(recording:)
      wrap_library_authorization_errors do
        RecordingStudioLibrary::Authorization.assert_library_enabled!(recording: recording)
      end
    end

    def library_owner_for(recording)
      RecordingStudioLibrary::Authorization.library_owner_for(recording)
    end

    def wrap_library_authorization_errors
      yield
    rescue RecordingStudioLibrary::Authorization::CapabilityNotEnabledError => e
      raise Authorization::CapabilityNotEnabledError, e.message
    rescue RecordingStudioLibrary::Authorization::NotAuthorizedError => e
      raise Authorization::NotAuthorizedError, e.message
    end
  end
end
