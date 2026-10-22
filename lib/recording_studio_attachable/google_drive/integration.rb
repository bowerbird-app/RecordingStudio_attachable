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
        return ::RecordingStudioGoogleDrive.configuration.oauth_provider_key if gem_loaded?

        :google_drive
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

      def picker_access(root:, actor:)
        token = ::RecordingStudioGoogleDrive::TokenStore.new(root: root, actor: actor).access_token
        expires_at = connection(root: root, actor: actor)&.expires_at
        [token, expires_at]
      end

      def reconnect_required?(error)
        gem_loaded? && error.is_a?(::RecordingStudioGoogleDrive::ReconnectRequired)
      end

      def request_error?(error)
        gem_loaded? && error.is_a?(::RecordingStudioGoogleDrive::RequestError)
      end

      def live_connection(root:, actor:)
        return unless oauth_loaded? && defined?(::RecordingStudioOauth::OutboundConnection)

        scope = ::RecordingStudioOauth::OutboundConnection.live.for_provider(provider_key)
        owned = actor_connection(scope, actor)
        return owned if owned
        return if root.nil? || !root.respond_to?(:id)

        scope.find_by(root_recording_id: root.id)
      end

      def actor_connection(scope, actor)
        return if actor.nil? || !actor.respond_to?(:id)

        scope.find_by(owner_actor_type: actor.class.name, owner_actor_id: actor.id)
      end
    end
  end
end
