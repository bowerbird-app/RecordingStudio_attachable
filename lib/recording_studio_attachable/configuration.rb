# frozen_string_literal: true

module RecordingStudioAttachable
  class Configuration
    class GoogleDriveConfiguration
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
        @client_id = nil
        @client_secret = nil
        @api_key = nil
        @app_id = nil
        @redirect_uri = nil
        @scopes = ["https://www.googleapis.com/auth/drive.readonly"]
        @access_type = "offline"
        @prompt = "consent"
        @include_granted_scopes = true
        @page_size = 25
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
        client_id.present? && client_secret.present? && redirect_uri.present?
      end

      def picker_configured?
        configured? && api_key.present? && app_id.present?
      end

      def to_h
        {
          enabled: enabled,
          client_id: client_id,
          client_secret: client_secret,
          api_key: api_key,
          app_id: app_id,
          redirect_uri: redirect_uri,
          scopes: scopes,
          access_type: access_type,
          prompt: prompt,
          include_granted_scopes: include_granted_scopes,
          page_size: page_size
        }
      end
    end

    ROLE_ALIASES = {
      viewer: :view,
      editor: :edit,
      viewing: :view,
      editing: :edit
    }.freeze

    attr_accessor :allowed_content_types,
                  :max_file_size,
                  :max_file_count,
                  :enabled_attachment_kinds,
                  :default_listing_scope,
                  :default_kind_filter,
                  :layout,
                  :auth_roles,
                  :classify_attachment_kind,
                  :authorize_with,
                  :google_drive

    attr_reader :upload_providers

    def initialize
      @allowed_content_types = ["image/*", "application/pdf"]
      @max_file_size = 25.megabytes
      @max_file_count = 20
      @enabled_attachment_kinds = %i[image file]
      @default_listing_scope = :direct
      @default_kind_filter = :all
      @layout = :blank
      @auth_roles = normalize_auth_roles(
        view: :viewer,
        upload: :editor,
        revise: :editor,
        remove: :admin,
        restore: :admin,
        download: :viewer
      )
      @classify_attachment_kind = ->(content_type) { content_type.to_s.start_with?("image/") ? "image" : "file" }
      @authorize_with = nil
      @google_drive = GoogleDriveConfiguration.new
      @upload_providers = []
    end

    def merge!(hash)
      return unless hash.respond_to?(:each)

      hash.each do |key, value|
        case key.to_sym
        when :auth_roles
          self.auth_roles = normalize_auth_roles(value)
        when :upload_providers
          self.upload_providers = value
        when :google_drive
          google_drive.merge!(value)
        else
          setter = "#{key}="
          public_send(setter, value) if respond_to?(setter)
        end
      end
    end

    def auth_role_for(action)
      auth_roles.fetch(action.to_sym)
    end

    def normalize_role(role)
      normalized = role.to_s.downcase.to_sym
      ROLE_ALIASES.fetch(normalized, normalized)
    end

    def attachment_kind_for(content_type, classifier: nil)
      normalize_attachment_kind((classifier || classify_attachment_kind).call(content_type))
    end

    def allowed_content_type?(content_type, allowed_content_types: self.allowed_content_types)
      allowed_content_types ||= self.allowed_content_types
      return true if allowed_content_types.blank?

      allowed_content_types.any? do |pattern|
        File.fnmatch?(pattern.to_s.downcase, content_type.to_s.downcase)
      end
    end

    def attachment_kind_enabled?(attachment_kind, enabled_attachment_kinds: self.enabled_attachment_kinds)
      enabled_attachment_kinds ||= self.enabled_attachment_kinds
      enabled_attachment_kinds.map { |kind| normalize_attachment_kind(kind) }.include?(normalize_attachment_kind(attachment_kind))
    end

    def normalize_attachment_kind(attachment_kind)
      attachment_kind.to_s.downcase
    end

    def normalize_auth_roles(roles)
      roles.to_h.transform_keys(&:to_sym).transform_values { |role| normalize_role(role) }
    end

    def upload_providers=(providers)
      @upload_providers = Array(providers).map { |provider| normalize_upload_provider(provider) }
    end

    def register_upload_provider(key = nil, **options)
      provider = if key.is_a?(RecordingStudioAttachable::UploadProvider)
                   key
                 else
                   normalize_upload_provider(options.merge(key: key))
                 end

      @upload_providers.reject! { |existing| existing.key == provider.key }
      @upload_providers << provider
      provider
    end

    def upload_provider(key)
      upload_providers.find { |provider| provider.key == key.to_sym }
    end

    def to_h
      {
        allowed_content_types: allowed_content_types,
        max_file_size: max_file_size,
        max_file_count: max_file_count,
        enabled_attachment_kinds: enabled_attachment_kinds,
        default_listing_scope: default_listing_scope,
        default_kind_filter: default_kind_filter,
        layout: layout,
        auth_roles: auth_roles,
        google_drive: google_drive.to_h
      }
    end

    private

    def normalize_upload_provider(provider)
      return provider if provider.is_a?(RecordingStudioAttachable::UploadProvider)

      RecordingStudioAttachable::UploadProvider.new(**provider.to_h.symbolize_keys)
    end
  end
end
