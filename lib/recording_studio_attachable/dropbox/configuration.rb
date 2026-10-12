# frozen_string_literal: true

module RecordingStudioAttachable
  module Dropbox
    class Configuration
      include RecordingStudioAttachable::Adapter::Configurable

      PLACEHOLDER_PREFIXES = {
        client_id: ["dummy-dropbox-client-id"],
        client_secret: ["dummy-dropbox-client-secret"]
      }.freeze

      attr_accessor :enabled,
                    :client_id,
                    :client_secret,
                    :redirect_uri,
                    :scopes

      def initialize
        @enabled = false
        @client_id = nil
        @client_secret = nil
        @redirect_uri = nil
        @scopes = %w[files.metadata.read files.content.read]
      end

      def configured?
        valid_credential?(client_id, :client_id) &&
          valid_credential?(client_secret, :client_secret) &&
          redirect_uri.present?
      end

      def available?
        enabled? && configured?
      end

      def to_h
        {
          enabled: enabled,
          client_id: client_id,
          client_secret: client_secret,
          redirect_uri: redirect_uri,
          scopes: scopes
        }
      end
    end
  end
end

RecordingStudioAttachable.register_adapter_configuration(
  :dropbox,
  RecordingStudioAttachable::Dropbox::Configuration
)
