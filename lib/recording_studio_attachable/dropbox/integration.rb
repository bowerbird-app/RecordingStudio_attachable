# frozen_string_literal: true

module RecordingStudioAttachable
  module Dropbox
    module Integration
      module_function

      def gem_loaded?
        defined?(::RecordingStudioDropbox)
      end

      def oauth_loaded?
        defined?(::RecordingStudioOauth)
      end

      def provider_key
        return :dropbox unless defined?(::RecordingStudioDropbox)

        ::RecordingStudioDropbox::OauthProvider::KEY
      end

      def client(root:, actor:)
        ::RecordingStudioDropbox::Client.new(
          token_provider: ::RecordingStudioDropbox::OauthToken.new(root: root, actor: actor)
        )
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

      def chooser_access(root:, actor:)
        ::RecordingStudioDropbox::OauthToken.new(root: root, actor: actor).call
      end

      def reconnect_required?(error)
        dropbox_error?(error, "ReconnectRequired")
      end

      def request_error?(error)
        dropbox_error?(error, "RequestError")
      end

      def dropbox_error?(error, name)
        return false unless defined?(::RecordingStudioDropbox)
        return false unless ::RecordingStudioDropbox.const_defined?(name, false)

        error.is_a?(::RecordingStudioDropbox.const_get(name))
      end
    end
  end
end
