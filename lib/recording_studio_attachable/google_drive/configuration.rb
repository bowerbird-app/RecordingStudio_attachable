# frozen_string_literal: true

module RecordingStudioAttachable
  module GoogleDrive
    class Configuration
      include RecordingStudioAttachable::Adapter::Configurable

      PLACEHOLDER_PREFIXES = {
        api_key: ["dummy-google-drive-api-key"],
        app_id: ["dummy-google-drive-app-id"]
      }.freeze

      attr_accessor :enabled, :api_key, :app_id, :page_size

      def initialize
        @enabled = false
        @api_key = nil
        @app_id = nil
        @page_size = 25
      end

      def picker_configured?
        valid_credential?(api_key, :api_key) && valid_credential?(app_id, :app_id)
      end

      alias configured? picker_configured?

      def available?
        enabled? && picker_configured? && Integration.gem_loaded?
      end

      def to_h
        {
          enabled: enabled,
          api_key: api_key,
          app_id: app_id,
          page_size: page_size
        }
      end
    end
  end
end

RecordingStudioAttachable.register_adapter_configuration(
  :google_drive,
  RecordingStudioAttachable::GoogleDrive::Configuration
)
