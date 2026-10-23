# frozen_string_literal: true

module RecordingStudioAttachable
  module GoogleDrive
    module Integration
      module_function

      def gem_loaded?
        defined?(::RecordingStudioGoogleDrive)
      end

      def oauth_loaded?
        defined?(::RecordingStudioOauth)
      end

      def provider_key
        return :google_drive unless defined?(::RecordingStudioGoogleDrive)

        ::RecordingStudioGoogleDrive.configuration.oauth_provider_key
      end

      def client(root:, actor:)
        ::RecordingStudioGoogleDrive::Client.for(root: root, actor: actor)
      end

      def connection(root:, actor:)
        return unless oauth_loaded?

        ::RecordingStudioOauth.connection_for(
          provider: provider_key,
          root: root,
          actor: actor
        )
      end

      def connection_status(root:, actor:)
        return :missing unless oauth_loaded?

        ::RecordingStudioOauth.connection_status(
          provider: provider_key,
          root: root,
          actor: actor
        )
      end

      def connection_id_for(root:, actor:)
        return unless oauth_loaded?

        ::RecordingStudioOauth.connection_id_for(
          provider: provider_key,
          root: root,
          actor: actor
        )
      end

      def picker_access(root:, actor:)
        token = ::RecordingStudioGoogleDrive.picker_access_token(root: root, actor: actor)
        expires_at = connection(root: root, actor: actor)&.expires_at
        [token, expires_at]
      end

      def reconnect_required?(error)
        drive_error?(error, "ReconnectRequired")
      end

      def request_error?(error)
        drive_error?(error, "RequestError")
      end

      def drive_error?(error, name)
        return false unless defined?(::RecordingStudioGoogleDrive)
        return false unless ::RecordingStudioGoogleDrive.const_defined?(name, false)

        error.is_a?(::RecordingStudioGoogleDrive.const_get(name))
      end
    end
  end
end
