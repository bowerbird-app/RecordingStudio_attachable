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

    ROLE_ALIASES = {
      viewer: :view,
      editor: :edit,
      viewing: :view,
      editing: :edit
    }.freeze

    URL_MODES = %i[rails direct].freeze
    UPLOAD_PRESENTATIONS = %i[page modal].freeze
    DEFAULT_PREPROCESSED_VARIANTS = %i[small med large].freeze

    attr_accessor :allowed_content_types,
                  :max_file_size,
                  :max_file_count,
                  :pending_upload_limit,
                  :unattached_blob_ttl,
                  :direct_upload_expires_in,
                  :purge_unattached_blobs,
                  :image_processing_enabled,
                  :image_processing_max_width,
                  :image_processing_max_height,
                  :image_processing_quality,
                  :enabled_attachment_kinds,
                  :default_listing_scope,
                  :default_kind_filter,
                  :auth_roles,
                  :classify_attachment_kind,
                  :authorize_with,
                  :direct_url_host,
                  :attachment_place_labels

    attr_reader :image_variants, :upload_providers, :storage_limit, :url_mode, :upload_presentation, :import_allowed_hosts, :layout

    def layout=(value)
      @layout = RecordingStudio::Layout.accept(value)
    end

    def initialize
      assign_defaults
      @adapter_configurations = {}
      RecordingStudioAttachable::Adapter.registry.each do |key, configuration_class|
        install_adapter_configuration(key, configuration_class.new)
      end
      @upload_providers = []
    end

    def install_adapter_configuration(key, configuration)
      adapter_key = key.to_sym
      @adapter_configurations[adapter_key] = configuration
      define_singleton_method(adapter_key) { @adapter_configurations.fetch(adapter_key) }
    end

    def adapter_configuration(key)
      @adapter_configurations[key.to_sym]
    end

    def merge!(hash)
      return unless hash.respond_to?(:each)

      hash.each { |key, value| merge_attribute!(key, value) }
    end

    def [](key)
      getter = key.to_s
      public_send(getter) if respond_to?(getter)
    end

    def []=(key, value)
      merge_attribute!(key, value)
      self[key]
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
      type = content_type.to_s.downcase.split(";").first.to_s.strip
      return false if type == "image/svg+xml" && !explicit_svg?(allowed_content_types)
      return true if allowed_content_types.blank?

      allowed_content_types.any? do |pattern|
        File.fnmatch?(pattern.to_s.downcase, type)
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

    def url_mode=(value)
      @url_mode = normalize_url_mode(value)
    end

    def resolve_url_mode(mode = nil)
      return url_mode if mode.nil?

      normalize_url_mode(mode)
    end

    # Effective list of variants processed after upload.
    #
    # Default (when the host has not set +preprocessed_variants+):
    # +DEFAULT_PREPROCESSED_VARIANTS+ (+small+, +med+, +large+) plus every
    # host-added custom name present in the current +image_variants+ map.
    # Other gem defaults (for example +square_med+, +xlarge+) are not
    # auto-included. The list is resolved at read time so a custom name added
    # later still joins the default.
    #
    # Explicit override: if the host assigns +preprocessed_variants+, that list
    # is used exactly (unknown names dropped).
    def preprocessed_variants
      return @preprocessed_variants if @preprocessed_variants_explicit

      default_preprocessed_variants
    end

    def preprocessed_variants=(variants)
      @preprocessed_variants_explicit = true
      @preprocessed_variants = normalize_preprocessed_variants(variants)
    end

    def preprocessed_variants_explicit?
      @preprocessed_variants_explicit
    end

    def host_added_image_variant_names
      image_variants.keys.reject { |name| DEFAULT_IMAGE_VARIANTS.key?(name) }
    end

    # How an Add button opens the standard upload page. :page navigates to it.
    # :modal opens it in a FlatPack modal on the current page.
    def upload_presentation=(value)
      @upload_presentation = normalize_upload_presentation(value)
    end

    def normalize_upload_presentation(value)
      return :page if value.blank?

      normalized = value.to_s.strip.downcase.to_sym
      return normalized if UPLOAD_PRESENTATIONS.include?(normalized)

      raise ArgumentError, "Unknown upload presentation: #{value.inspect}. Use :page or :modal."
    end

    def import_allowed_hosts=(hosts)
      @import_allowed_hosts = Array(hosts).filter_map { |host| host.to_s.strip.downcase.presence }
    end

    def storage_limit=(value)
      normalized = value.is_a?(String) ? value.strip : value
      @storage_limit = normalized.presence
    end

    def to_h
      {
        allowed_content_types: allowed_content_types,
        max_file_size: max_file_size,
        max_file_count: max_file_count,
        pending_upload_limit: pending_upload_limit,
        unattached_blob_ttl: unattached_blob_ttl,
        direct_upload_expires_in: direct_upload_expires_in,
        purge_unattached_blobs: purge_unattached_blobs,
        import_allowed_hosts: import_allowed_hosts,
        storage_limit: storage_limit,
        image_processing_enabled: image_processing_enabled,
        image_processing_max_width: image_processing_max_width,
        image_processing_max_height: image_processing_max_height,
        image_processing_quality: image_processing_quality,
        image_variants: image_variants,
        url_mode: url_mode,
        direct_url_host: direct_url_host,
        preprocessed_variants: preprocessed_variants,
        enabled_attachment_kinds: enabled_attachment_kinds,
        default_listing_scope: default_listing_scope,
        default_kind_filter: default_kind_filter,
        layout: layout,
        upload_presentation: upload_presentation,
        auth_roles: auth_roles
      }.merge(adapter_configurations_hash)
    end

    # Labels for places that reuse this attachment. Empty unless a host sets
    # attachment_place_labels. The attachment page warns before trash when
    # the list is present.
    def attachment_place_labels_for(attachment_recording)
      resolver = attachment_place_labels
      return [] unless resolver.respond_to?(:call)

      Array(resolver.call(attachment_recording)).filter_map { |label| label.to_s.strip.presence }
    end

    private

    def explicit_svg?(allowed_content_types)
      Array(allowed_content_types).any? { |pattern| pattern.to_s.downcase.strip == "image/svg+xml" }
    end

    def assign_defaults
      @allowed_content_types = ["image/*", "application/pdf"]
      @max_file_size = 25.megabytes
      @max_file_count = 20
      @pending_upload_limit = 20
      @unattached_blob_ttl = 24.hours
      @direct_upload_expires_in = 5.minutes
      @purge_unattached_blobs = false
      @import_allowed_hosts = []
      @storage_limit = nil
      @image_processing_enabled = false
      @image_processing_max_width = 2560
      @image_processing_max_height = 2560
      @image_processing_quality = 0.82
      @image_variants = default_image_variants
      @url_mode = :rails
      @upload_presentation = :page
      @direct_url_host = nil
      @preprocessed_variants_explicit = false
      @preprocessed_variants = nil
      @enabled_attachment_kinds = %i[image file]
      @default_listing_scope = :direct
      @default_kind_filter = :all
      @layout = nil
      @auth_roles = default_auth_roles
      @classify_attachment_kind = default_attachment_kind_classifier
      @authorize_with = nil
      @attachment_place_labels = nil
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
      adapter_key = key.to_sym
      if @adapter_configurations.key?(adapter_key)
        @adapter_configurations[adapter_key].merge!(value)
        return
      end

      setter = merge_setter_for(key)
      public_send(setter, merge_value(key, value)) if respond_to?(setter)
    end

    def adapter_configurations_hash
      @adapter_configurations.transform_values(&:to_h)
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
        next unless transformations.respond_to?(:to_h)

        transforms = transformations.to_h.deep_symbolize_keys
        normalized[key] = if normalized.key?(key)
                            normalized.fetch(key).merge(transforms)
                          else
                            transforms
                          end
      end

      normalized
    end

    def normalize_url_mode(value)
      normalized = value.to_s.strip.downcase.to_sym
      return normalized if URL_MODES.include?(normalized)

      raise ArgumentError, "url_mode must be :rails or :direct (got #{value.inspect})"
    end

    def normalize_preprocessed_variants(variants)
      Array(variants).filter_map do |name|
        key = name.to_sym
        key if image_variants.key?(key)
      end.uniq
    end

    def default_preprocessed_variants
      (DEFAULT_PREPROCESSED_VARIANTS + host_added_image_variant_names).uniq
    end
  end
end
