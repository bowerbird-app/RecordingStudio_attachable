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
    assert_equal 20, @configuration.pending_upload_limit
    assert_equal 24.hours, @configuration.unattached_blob_ttl
    assert_equal 5.minutes, @configuration.direct_upload_expires_in
    assert_equal false, @configuration.purge_unattached_blobs
    assert_equal [], @configuration.import_allowed_hosts
    assert_nil @configuration.storage_limit
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
    assert_equal :rails, @configuration.url_mode
    assert_nil @configuration.direct_url_host
    assert_equal %i[small med large], @configuration.preprocessed_variants
    assert_not @configuration.preprocessed_variants_explicit?
    assert_equal :direct, @configuration.default_listing_scope
    assert_equal :all, @configuration.default_kind_filter
    assert_equal :blank, @configuration.layout
    assert_empty @configuration.upload_providers
    assert_equal :view, @configuration.auth_role_for(:view)
    assert_equal :edit, @configuration.auth_role_for(:upload)
    assert_nil @configuration.attachment_place_labels
    assert_equal [], @configuration.attachment_place_labels_for(Object.new)
  end

  def test_attachment_place_labels_use_the_host_proc
    @configuration.attachment_place_labels = ->(_recording) { ["Kiln shots", " ", nil] }

    assert_equal ["Kiln shots"], @configuration.attachment_place_labels_for(Object.new)
  end

  def test_url_mode_accepts_rails_and_direct
    @configuration.url_mode = "direct"
    assert_equal :direct, @configuration.url_mode

    @configuration.url_mode = :rails
    assert_equal :rails, @configuration.url_mode
  end

  def test_url_mode_rejects_unknown_values
    error = assert_raises(ArgumentError) { @configuration.url_mode = :cdn }

    assert_match(/url_mode must be :rails or :direct/, error.message)
  end

  def test_preprocessed_variants_keeps_known_variant_names_only
    @configuration.preprocessed_variants = %i[small mystery med xlarge]

    assert_equal %i[small med xlarge], @configuration.preprocessed_variants
    assert @configuration.preprocessed_variants_explicit?
  end

  def test_default_preprocessed_variants_include_host_added_custom_names
    @configuration.image_variants = {
      poster: { resize_to_limit: [1280, 720] },
      large: { resize_to_limit: [1800, 1800] }
    }

    assert_equal %i[small med large poster], @configuration.preprocessed_variants
    assert_includes @configuration.host_added_image_variant_names, :poster
    assert_not_includes @configuration.preprocessed_variants, :square_med
    assert_not_includes @configuration.preprocessed_variants, :xlarge
  end

  def test_default_preprocessed_variants_resolve_custom_names_added_later
    assert_equal %i[small med large], @configuration.preprocessed_variants

    @configuration.image_variants = { poster: { resize_to_limit: [1280, 720] } }

    assert_equal %i[small med large poster], @configuration.preprocessed_variants
  end

  def test_explicit_preprocessed_variants_override_wins_over_host_added_defaults
    @configuration.image_variants = { poster: { resize_to_limit: [1280, 720] } }
    @configuration.preprocessed_variants = %i[small poster]

    assert_equal %i[small poster], @configuration.preprocessed_variants
    assert_not_includes @configuration.preprocessed_variants, :med
    assert_not_includes @configuration.preprocessed_variants, :large
  end

  def test_resolve_url_mode_uses_config_default_or_override
    @configuration.url_mode = :rails

    assert_equal :rails, @configuration.resolve_url_mode
    assert_equal :direct, @configuration.resolve_url_mode(:direct)
  end

  def test_register_upload_provider_stores_provider_by_key
    provider = @configuration.register_upload_provider(
      :my_cloud,
      label: "My Cloud",
      url: "/imports/my_cloud",
      icon: "cloud"
    )

    assert_equal provider, @configuration.upload_provider(:my_cloud)
    assert_equal [:my_cloud], @configuration.upload_providers.map(&:key)
  end

  def test_register_upload_provider_replaces_existing_provider_with_same_key
    @configuration.register_upload_provider(:my_cloud, label: "Old", url: "/imports/old")

    provider = @configuration.register_upload_provider(:my_cloud, label: "New", url: "/imports/new")

    assert_equal [provider], @configuration.upload_providers
    assert_equal "New", @configuration.upload_provider(:my_cloud).label
  end

  def test_register_upload_provider_accepts_existing_provider_instances
    provider = RecordingStudioAttachable::UploadProvider.new(key: :my_cloud, label: "My Cloud", url: "/imports/my_cloud")

    returned = @configuration.register_upload_provider(provider)

    assert_same provider, returned
    assert_same provider, @configuration.upload_provider(:my_cloud)
  end

  def test_upload_providers_assignment_normalizes_hashes
    @configuration.upload_providers = [{ key: :my_cloud, label: "My Cloud", url: "/imports/my_cloud" }]

    provider = @configuration.upload_provider(:my_cloud)
    assert_instance_of RecordingStudioAttachable::UploadProvider, provider
    assert_equal "My Cloud", provider.label
  end

  def test_upload_provider_callables_can_use_route_helpers_without_full_view_context
    provider = @configuration.register_upload_provider(
      :my_cloud,
      label: "My Cloud",
      url: ->(route_helpers:, recording:) { route_helpers.recording_imports_path(recording_id: recording.id) }
    )
    route_helpers = Object.new
    route_helpers.define_singleton_method(:recording_imports_path) { |recording_id:| "/imports/#{recording_id}" }
    view_context = ViewContextWithRoutes.new(route_helpers)
    recording = Struct.new(:id).new("rec-1")

    assert_equal "/imports/rec-1", provider.button_options(view_context: view_context, recording: recording)[:href]
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
                 provider.button_options(view_context: view_context, recording: recording)[:href]
  end

  def test_merge_normalizes_auth_roles
    @configuration[:auth_roles] = { view: :viewer, upload: :editor }

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
        poster: { resize_to_limit: [1280, 720] }
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
    assert_equal({ resize_to_limit: [1280, 720] }, @configuration.image_variant(:poster))
    assert_equal %i[small med large poster], @configuration.preprocessed_variants
    assert_equal :subtree, @configuration.default_listing_scope
  end
end
