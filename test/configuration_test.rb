# frozen_string_literal: true

require "test_helper"

class ConfigurationTest < Minitest::Test
  class ViewContextWithRoutes
    attr_reader :main_app

    def initialize(main_app)
      @main_app = main_app
    end

    def method_missing(name, *args, **kwargs, &)
      return main_app.public_send(name, *args, **kwargs, &) if main_app.respond_to?(name)

      super
    end

    def respond_to_missing?(name, include_private = false)
      main_app.respond_to?(name, include_private) || super
    end
  end

  def setup
    @configuration = RecordingStudioAttachable::Configuration.new
  end

  def test_defaults_match_attachable_expectations
    assert_equal ["image/*", "application/pdf"], @configuration.allowed_content_types
    assert_equal 20, @configuration.max_file_count
    assert_not @configuration.image_processing_enabled
    assert_equal 2560, @configuration.image_processing_max_width
    assert_equal 2560, @configuration.image_processing_max_height
    assert_equal 0.82, @configuration.image_processing_quality
    assert_equal(
      {
        square_small: { resize_to_fill: [128, 128] },
        square_med: { resize_to_fill: [400, 400] },
        square_large: { resize_to_fill: [800, 800] },
        small: { resize_to_limit: [480, 480] },
        med: { resize_to_limit: [960, 960] },
        large: { resize_to_limit: [1600, 1600] },
        xlarge: { resize_to_limit: [2400, 2400] }
      },
      @configuration.image_variants
    )
    assert_equal :direct, @configuration.default_listing_scope
    assert_equal :all, @configuration.default_kind_filter
    assert_equal :blank, @configuration.layout
    assert_empty @configuration.upload_providers
    assert_equal :view, @configuration.auth_role_for(:view)
    assert_equal :edit, @configuration.auth_role_for(:upload)
    assert_not @configuration.google_drive.enabled?
    assert_not @configuration.google_drive.configured?
    assert_not @configuration.google_drive.picker_configured?
    assert_equal ["https://www.googleapis.com/auth/drive.readonly"], @configuration.google_drive.scopes
  end

  def test_register_upload_provider_stores_provider_by_key
    provider = @configuration.register_upload_provider(
      :google_drive,
      label: "Google Drive",
      url: "/imports/google_drive",
      icon: "cloud"
    )

    assert_equal provider, @configuration.upload_provider(:google_drive)
    assert_equal [:google_drive], @configuration.upload_providers.map(&:key)
  end

  def test_register_upload_provider_replaces_existing_provider_with_same_key
    @configuration.register_upload_provider(:google_drive, label: "Old", url: "/imports/old")

    provider = @configuration.register_upload_provider(:google_drive, label: "New", url: "/imports/new")

    assert_equal [provider], @configuration.upload_providers
    assert_equal "New", @configuration.upload_provider(:google_drive).label
  end

  def test_register_upload_provider_accepts_existing_provider_instances
    provider = RecordingStudioAttachable::UploadProvider.new(key: :dropbox, label: "Dropbox", url: "/imports/dropbox")

    returned = @configuration.register_upload_provider(provider)

    assert_same provider, returned
    assert_same provider, @configuration.upload_provider(:dropbox)
  end

  def test_upload_providers_assignment_normalizes_hashes
    @configuration.upload_providers = [{ key: :dropbox, label: "Dropbox", url: "/imports/dropbox" }]

    provider = @configuration.upload_provider(:dropbox)
    assert_instance_of RecordingStudioAttachable::UploadProvider, provider
    assert_equal "Dropbox", provider.label
  end

  def test_upload_provider_callables_can_use_route_helpers_without_full_view_context
    provider = @configuration.register_upload_provider(
      :google_drive,
      label: "Google Drive",
      url: ->(route_helpers:, recording:) { route_helpers.recording_imports_path(recording_id: recording.id) }
    )
    route_helpers = Object.new
    route_helpers.define_singleton_method(:recording_imports_path) { |recording_id:| "/imports/#{recording_id}" }
    view_context = ViewContextWithRoutes.new(route_helpers)
    recording = Struct.new(:id).new("rec-1")

    assert_equal "/imports/rec-1", provider.button_options(view_context: view_context, recording: recording)[:url]
  end

  def test_upload_provider_callables_can_use_mounted_engine_routes_via_route_helpers
    provider = @configuration.register_upload_provider(
      :mounted_provider,
      label: "Mounted provider",
      url: ->(route_helpers:, recording:) { route_helpers.mounted_provider.recording_imports_path(recording) }
    )
    mounted_proxy = Object.new
    mounted_proxy.define_singleton_method(:recording_imports_path) { |record| "/mounted_provider/recordings/#{record.id}/imports" }
    route_helpers = Object.new
    route_helpers.define_singleton_method(:mounted_provider) { mounted_proxy }
    view_context = ViewContextWithRoutes.new(route_helpers)
    recording = Struct.new(:id).new("rec-1")

    assert_equal "/mounted_provider/recordings/rec-1/imports",
                 provider.button_options(view_context: view_context, recording: recording)[:url]
  end

  def test_merge_normalizes_auth_roles
    @configuration.merge!(auth_roles: { view: :viewer, upload: :editor })

    assert_equal :view, @configuration.auth_role_for(:view)
    assert_equal :edit, @configuration.auth_role_for(:upload)
  end

  def test_merge_updates_known_attributes_and_ignores_unknown_ones
    @configuration.merge!(
      max_file_size: 5.megabytes,
      max_file_count: 8,
      image_processing_enabled: true,
      image_processing_max_width: 1600,
      image_processing_max_height: 1200,
      image_processing_quality: 0.75,
      image_variants: {
        large: { resize_to_limit: [1800, 1800] },
        square_small: { resize_to_fill: [96, 96] },
        unknown: { resize_to_limit: [1, 1] }
      },
      default_listing_scope: :subtree,
      unknown_setting: true
    )

    assert_equal 5.megabytes, @configuration.max_file_size
    assert_equal 8, @configuration.max_file_count
    assert @configuration.image_processing_enabled
    assert_equal 1600, @configuration.image_processing_max_width
    assert_equal 1200, @configuration.image_processing_max_height
    assert_equal 0.75, @configuration.image_processing_quality
    assert_equal({ resize_to_limit: [1800, 1800] }, @configuration.image_variant(:large))
    assert_equal({ resize_to_fill: [96, 96] }, @configuration.image_variant(:square_small))
    assert_nil @configuration.image_variant(:unknown)
    assert_equal :subtree, @configuration.default_listing_scope
  end

  def test_merge_updates_google_drive_configuration
    @configuration.merge!(google_drive: {
                            enabled: true,
                            client_id: "client-id",
                            client_secret: "client-secret",
                            api_key: "api-key",
                            app_id: "app-id",
                            redirect_uri: "https://example.test/recording_studio_attachable/google_drive/oauth/callback",
                            page_size: 10
                          })

    assert @configuration.google_drive.enabled?
    assert @configuration.google_drive.configured?
    assert @configuration.google_drive.picker_configured?
    assert_equal "client-id", @configuration.google_drive.client_id
    assert_equal 10, @configuration.google_drive.page_size
  end

  def test_google_drive_picker_configuration_rejects_dummy_placeholder_values
    @configuration.merge!(google_drive: {
                            enabled: true,
                            client_id: "client-id",
                            client_secret: "client-secret",
                            redirect_uri: "https://example.test/recording_studio_attachable/google_drive/oauth/callback",
                            api_key: "dummy-google-drive-api-key",
                            app_id: "dummy-google-drive-app-id"
                          })

    assert @configuration.google_drive.configured?
    assert_not @configuration.google_drive.picker_configured?
  end

  def test_google_drive_merge_returns_self_and_ignores_unknown_keys
    google_drive = @configuration.google_drive

    returned = google_drive.merge!(enabled: true, unknown: "ignored")

    assert_same google_drive, returned
    assert google_drive.enabled?
    assert_not google_drive.respond_to?(:unknown)
  end

  def test_merge_ignores_non_enumerable_inputs
    snapshot = @configuration.to_h

    @configuration.merge!(nil)

    assert_equal snapshot, @configuration.to_h
  end

  def test_allowed_content_type_supports_wildcards
    assert @configuration.allowed_content_type?("image/png")
    assert_not @configuration.allowed_content_type?("text/plain")
  end

  def test_allowed_content_type_accepts_blank_overrides
    assert @configuration.allowed_content_type?("text/plain", allowed_content_types: [])
  end

  def test_attachment_kind_for_uses_classifier
    assert_equal "image", @configuration.attachment_kind_for("image/jpeg")
    assert_equal "file", @configuration.attachment_kind_for("application/pdf")
  end

  def test_attachment_kind_for_accepts_custom_classifier
    classifier = ->(_content_type) { :IMAGE }

    assert_equal "image", @configuration.attachment_kind_for("text/plain", classifier: classifier)
  end

  def test_attachment_kind_enabled_normalizes_values
    assert @configuration.attachment_kind_enabled?("IMAGE", enabled_attachment_kinds: ["image"])
    assert_not @configuration.attachment_kind_enabled?("audio", enabled_attachment_kinds: ["image"])
  end

  def test_attachment_kind_enabled_falls_back_to_global_configuration_when_override_is_nil
    @configuration.enabled_attachment_kinds = %i[file]

    assert @configuration.attachment_kind_enabled?("file", enabled_attachment_kinds: nil)
    assert_not @configuration.attachment_kind_enabled?("image", enabled_attachment_kinds: nil)
  end

  def test_upload_provider_returns_nil_for_missing_keys
    assert_nil @configuration.upload_provider(:missing)
  end

  def test_normalize_role_maps_aliases_and_custom_roles
    assert_equal :view, @configuration.normalize_role("Viewing")
    assert_equal :edit, @configuration.normalize_role(:editor)
    assert_equal :admin, @configuration.normalize_role(:admin)
  end

  def test_normalize_auth_roles_symbolizes_actions_and_roles
    roles = @configuration.normalize_auth_roles("view" => "viewer", upload: "Editor")

    assert_equal({ view: :view, upload: :edit }, roles)
  end

  def test_to_h_reflects_current_values
    @configuration.layout = :application
    @configuration.enabled_attachment_kinds = %i[file]

    assert_equal(
      {
        allowed_content_types: ["image/*", "application/pdf"],
        max_file_size: 25.megabytes,
        max_file_count: 20,
        image_processing_enabled: false,
        image_processing_max_width: 2560,
        image_processing_max_height: 2560,
        image_processing_quality: 0.82,
        image_variants: {
          square_small: { resize_to_fill: [128, 128] },
          square_med: { resize_to_fill: [400, 400] },
          square_large: { resize_to_fill: [800, 800] },
          small: { resize_to_limit: [480, 480] },
          med: { resize_to_limit: [960, 960] },
          large: { resize_to_limit: [1600, 1600] },
          xlarge: { resize_to_limit: [2400, 2400] }
        },
        enabled_attachment_kinds: %i[file],
        default_listing_scope: :direct,
        default_kind_filter: :all,
        layout: :application,
        auth_roles: @configuration.auth_roles,
        google_drive: @configuration.google_drive.to_h
      },
      @configuration.to_h
    )
  end
end
