# frozen_string_literal: true

module RecordingStudioAttachable
  module GoogleDrive
    class Configuration
      PLACEHOLDER_PREFIXES = {
        client_id: ["dummy-google-drive-client-id"],
        client_secret: ["dummy-google-drive-client-secret"],
        api_key: ["dummy-google-drive-api-key"],
        app_id: ["dummy-google-drive-app-id"]
      }.freeze

      attr_accessor :enabled,
                    :client_id,
                    :client_secret,
                    :api_key,
                    :app_id,
                    :redirect_uri,
                    :scopes,
                    :access_type,
                    :prompt,
                    :include_granted_scopes,
                    :page_size

      def initialize
        @enabled = false
        reset_credentials
        reset_oauth_defaults
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
        valid_google_drive_value?(client_id, :client_id) &&
          valid_google_drive_value?(client_secret, :client_secret) &&
          redirect_uri.present?
      end

      def picker_configured?
        configured? && valid_google_drive_value?(api_key, :api_key) && valid_google_drive_value?(app_id, :app_id)
      end

      def available?
        enabled? && picker_configured?
      end

      def to_h
        credential_settings.merge(oauth_settings)
      end

      private

      def reset_credentials
        @client_id = nil
        @client_secret = nil
        @api_key = nil
        @app_id = nil
        @redirect_uri = nil
      end

      def reset_oauth_defaults
        @scopes = ["https://www.googleapis.com/auth/drive.readonly"]
        @access_type = "offline"
        @prompt = "consent"
        @include_granted_scopes = true
        @page_size = 25
      end

      def credential_settings
        {
          enabled: enabled,
          client_id: client_id,
          client_secret: client_secret,
          api_key: api_key,
          app_id: app_id
        }
      end

      def oauth_settings
        {
          redirect_uri: redirect_uri,
          scopes: scopes,
          access_type: access_type,
          prompt: prompt,
          include_granted_scopes: include_granted_scopes,
          page_size: page_size
        }
      end

      def valid_google_drive_value?(value, field)
        normalized = value.to_s.strip
        return false if normalized.blank?

        Array(PLACEHOLDER_PREFIXES[field]).exclude?(normalized)
      end
    end
  end
end

RecordingStudioAttachable.register_adapter_configuration(
  :google_drive,
  RecordingStudioAttachable::GoogleDrive::Configuration
)
