# frozen_string_literal: true

module RecordingStudioAttachable
  class Configuration
    DEFAULT_IMAGE_VARIANTS = {
      square_small: { resize_to_fill: [128, 128] },
      square_med: { resize_to_fill: [400, 400] },
      square_large: { resize_to_fill: [800, 800] },
      small: { resize_to_limit: [480, 480] },
      med: { resize_to_limit: [960, 960] },
      large: { resize_to_limit: [1600, 1600] },
      xlarge: { resize_to_limit: [2400, 2400] }
    }.freeze

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
                  :image_processing_enabled,
                  :image_processing_max_width,
                  :image_processing_max_height,
                  :image_processing_quality,
                  :enabled_attachment_kinds,
                  :default_listing_scope,
                  :default_kind_filter,
                  :layout,
                  :auth_roles,
                  :classify_attachment_kind,
                  :authorize_with,
                  :google_drive

    attr_reader :image_variants, :upload_providers

    def initialize
      assign_defaults
      @google_drive = GoogleDriveConfiguration.new
      @upload_providers = []
    end

    def merge!(hash)
      return unless hash.respond_to?(:each)

      hash.each { |key, value| merge_attribute!(key, value) }
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

    def image_variant(name)
      image_variants[name.to_sym]
    end

    def image_variants=(variants)
      @image_variants = normalize_image_variants(variants)
    end

    def to_h
      {
        allowed_content_types: allowed_content_types,
        max_file_size: max_file_size,
        max_file_count: max_file_count,
        image_processing_enabled: image_processing_enabled,
        image_processing_max_width: image_processing_max_width,
        image_processing_max_height: image_processing_max_height,
        image_processing_quality: image_processing_quality,
        image_variants: image_variants,
        enabled_attachment_kinds: enabled_attachment_kinds,
        default_listing_scope: default_listing_scope,
        default_kind_filter: default_kind_filter,
        layout: layout,
        auth_roles: auth_roles,
        google_drive: google_drive.to_h
      }
    end

    private

    def assign_defaults
      @allowed_content_types = ["image/*", "application/pdf"]
      @max_file_size = 25.megabytes
      @max_file_count = 20
      @image_processing_enabled = false
      @image_processing_max_width = 2560
      @image_processing_max_height = 2560
      @image_processing_quality = 0.82
      @image_variants = default_image_variants
      @enabled_attachment_kinds = %i[image file]
      @default_listing_scope = :direct
      @default_kind_filter = :all
      @layout = :blank
      @auth_roles = default_auth_roles
      @classify_attachment_kind = default_attachment_kind_classifier
      @authorize_with = nil
    end

    def default_auth_roles
      normalize_auth_roles(
        view: :viewer,
        upload: :editor,
        revise: :editor,
        remove: :admin,
        restore: :admin,
        download: :viewer
      )
    end

    def default_attachment_kind_classifier
      ->(content_type) { content_type.to_s.start_with?("image/") ? "image" : "file" }
    end

    def merge_attribute!(key, value)
      if key.to_sym == :google_drive
        google_drive.merge!(value)
        return
      end

      setter = merge_setter_for(key)
      public_send(setter, merge_value(key, value)) if respond_to?(setter)
    end

    def merge_setter_for(key)
      key.to_sym == :upload_providers ? "upload_providers=" : "#{key}="
    end

    def merge_value(key, value)
      key.to_sym == :auth_roles ? normalize_auth_roles(value) : value
    end

    def normalize_upload_provider(provider)
      return provider if provider.is_a?(RecordingStudioAttachable::UploadProvider)

      RecordingStudioAttachable::UploadProvider.new(**provider.to_h.symbolize_keys)
    end

    def default_image_variants
      DEFAULT_IMAGE_VARIANTS.deep_dup
    end

    def normalize_image_variants(variants)
      normalized = default_image_variants
      return normalized unless variants.respond_to?(:each)

      variants.each do |name, transformations|
        key = name.to_sym
        next unless normalized.key?(key)
        next unless transformations.respond_to?(:to_h)

        normalized[key] = normalized.fetch(key).merge(transformations.to_h.deep_symbolize_keys)
      end

      normalized
    end
  end
end
