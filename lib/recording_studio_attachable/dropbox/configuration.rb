# frozen_string_literal: true

require_relative "integration"

module RecordingStudioAttachable
  module Dropbox
    class Configuration
      include RecordingStudioAttachable::Adapter::Configurable

      PLACEHOLDER_PREFIXES = {
        client_id: ["dummy-dropbox-client-id"]
      }.freeze

      attr_accessor :enabled, :client_id, :page_size

      def initialize
        @enabled = false
        @client_id = nil
        @page_size = 25
      end

      def chooser_configured?
        valid_credential?(client_id, :client_id)
      end

      alias configured? chooser_configured?

      def available?
        enabled? && chooser_configured? && Integration.gem_loaded?
      end

      def to_h
        {
          enabled: enabled,
          client_id: client_id,
          page_size: page_size
        }
      end
    end
  end
end

RecordingStudioAttachable.register_adapter_configuration(
  :dropbox,
  RecordingStudioAttachable::Dropbox::Configuration
)
