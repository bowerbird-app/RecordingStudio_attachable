# frozen_string_literal: true

module RecordingStudioAttachable
  module Dropbox
    class Configuration
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

      def merge!(attributes)
        return self unless attributes.respond_to?(:each)

        attributes.each do |key, value|
          setter = "#{key}="
          public_send(setter, value) if respond_to?(setter)
        end

        self
      end

      def enabled?
        !!enabled
      end

      def configured?
        valid_dropbox_value?(client_id, :client_id) &&
          valid_dropbox_value?(client_secret, :client_secret) &&
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

      private

      def valid_dropbox_value?(value, field)
        normalized = value.to_s.strip
        return false if normalized.blank?

        Array(PLACEHOLDER_PREFIXES[field]).exclude?(normalized)
      end
    end
  end
end

RecordingStudioAttachable.register_adapter_configuration(
  :dropbox,
  RecordingStudioAttachable::Dropbox::Configuration
)
