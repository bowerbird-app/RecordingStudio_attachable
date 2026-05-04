# frozen_string_literal: true

module RecordingStudioAttachable
  class Configuration
    ROLE_ALIASES = {
      viewer: :view,
      editor: :edit,
      viewing: :view,
      editing: :edit
    }.freeze

    attr_accessor :allowed_content_types,
                  :max_file_size,
                  :enabled_attachment_kinds,
                  :default_listing_scope,
                  :default_kind_filter,
                  :layout,
                  :auth_roles,
                  :placement,
                  :trashable_required_for_restore,
                  :classify_attachment_kind,
                  :authorize_with

    def initialize
      @allowed_content_types = ["image/*", "application/pdf"]
      @max_file_size = 25.megabytes
      @enabled_attachment_kinds = %i[image file]
      @default_listing_scope = :direct
      @default_kind_filter = :all
      @layout = :blank_upload
      @auth_roles = normalize_auth_roles(
        view: :viewer,
        upload: :editor,
        revise: :editor,
        remove: :admin,
        restore: :admin,
        download: :viewer
      )
      @placement = :children_only
      @trashable_required_for_restore = true
      @classify_attachment_kind = ->(content_type) { content_type.to_s.start_with?("image/") ? "image" : "file" }
      @authorize_with = nil
    end

    def merge!(hash)
      return unless hash.respond_to?(:each)

      hash.each do |key, value|
        case key.to_sym
        when :auth_roles
          self.auth_roles = normalize_auth_roles(value)
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

    def attachment_kind_for(content_type)
      normalize_attachment_kind(classify_attachment_kind.call(content_type))
    end

    def allowed_content_type?(content_type)
      return true if allowed_content_types.blank?

      allowed_content_types.any? do |pattern|
        File.fnmatch?(pattern.to_s.downcase, content_type.to_s.downcase)
      end
    end

    def attachment_kind_enabled?(attachment_kind)
      enabled_attachment_kinds.map { |kind| normalize_attachment_kind(kind) }.include?(normalize_attachment_kind(attachment_kind))
    end

    def normalize_attachment_kind(attachment_kind)
      attachment_kind.to_s.downcase
    end

    def normalize_auth_roles(roles)
      roles.to_h.transform_keys(&:to_sym).transform_values { |role| normalize_role(role) }
    end

    def to_h
      {
        allowed_content_types: allowed_content_types,
        max_file_size: max_file_size,
        enabled_attachment_kinds: enabled_attachment_kinds,
        default_listing_scope: default_listing_scope,
        default_kind_filter: default_kind_filter,
        layout: layout,
        auth_roles: auth_roles,
        placement: placement,
        trashable_required_for_restore: trashable_required_for_restore
      }
    end
  end
end
