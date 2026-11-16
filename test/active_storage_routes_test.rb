# frozen_string_literal: true

require "test_helper"
require "fileutils"
require "tmpdir"

class ActiveStorageRoutesTest < Minitest::Test
  def setup
    @original_warning = RecordingStudioAttachable.configuration.warn_on_active_storage_routes
  end

  def teardown
    RecordingStudioAttachable.configuration.warn_on_active_storage_routes = @original_warning
  end

  def test_boot_warning_fires_when_direct_uploads_is_drawn
    warnings = []

    with_routes(:rails_direct_uploads, warnings, warn: true) do
      RecordingStudioAttachable::ActiveStorageRoutes.warn_if_exposed
    end

    assert_equal [RecordingStudioAttachable::ActiveStorageRoutes::WARNING], warnings
    assert_includes warnings.first, "direct_uploads"
    assert_includes warnings.first, "warn_on_active_storage_routes"
  end

  def test_boot_warning_is_silent_when_direct_uploads_is_not_drawn
    warnings = []

    with_routes(:rails_service_blob, warnings, warn: true) do
      RecordingStudioAttachable::ActiveStorageRoutes.warn_if_exposed
    end

    assert_empty warnings
  end

  def test_boot_warning_is_silent_when_the_flag_is_off
    warnings = []

    with_routes(:rails_direct_uploads, warnings, warn: false) do
      RecordingStudioAttachable::ActiveStorageRoutes.warn_if_exposed
    end

    assert_empty warnings
  end

  def test_route_load_hook_warns_when_the_route_is_drawn
    warnings = []

    with_routes(:rails_direct_uploads, warnings, warn: true) do
      ActiveSupport.run_load_hooks(:after_routes_loaded, Object.new)
    end

    assert_equal [RecordingStudioAttachable::ActiveStorageRoutes::WARNING], warnings
  end

  def test_draw_keeps_signed_redirects_and_disk_routes_for_disk
    names = drawn_names("local:\n  service: Disk\n", :local)

    assert_includes names, :rails_service_blob
    assert_includes names, :rails_blob_representation
    assert_includes names, :rails_disk_service
    assert_includes names, :update_rails_disk_service
    assert_not_includes names, :rails_direct_uploads
    assert_not_includes names, :rails_service_blob_proxy
    assert_not_includes names, :rails_blob_representation_proxy
  end

  def test_draw_skips_disk_routes_when_the_service_is_not_disk
    names = drawn_names("amazon:\n  service: S3\n", :amazon)

    assert_includes names, :rails_service_blob
    assert_includes names, :rails_blob_representation
    assert_not_includes names, :rails_disk_service
    assert_not_includes names, :update_rails_disk_service
    assert_not_includes names, :rails_direct_uploads
  end

  private

  def with_routes(route_name, warnings, warn:, &block)
    RecordingStudioAttachable.configuration.warn_on_active_storage_routes = warn
    logger = Object.new
    logger.define_singleton_method(:warn) { |message| warnings << message }
    route_set = named_routes(route_name)
    app = Object.new
    app.define_singleton_method(:routes) { route_set }

    Rails.stub(:logger, logger) do
      Rails.stub(:application, app, &block)
    end
  end

  def named_routes(route_name)
    named = Object.new
    named.define_singleton_method(:names) { [route_name] }
    routes = Object.new
    routes.define_singleton_method(:named_routes) { named }
    routes
  end

  def drawn_names(yaml, service)
    Dir.mktmpdir do |dir|
      FileUtils.mkdir_p(File.join(dir, "config"))
      File.write(File.join(dir, "config/storage.yml"), yaml)
      app = storage_app(dir, service)
      routes = ActionDispatch::Routing::RouteSet.new
      routes.draw { RecordingStudioAttachable::ActiveStorageRoutes.draw(self, app: app) }
      routes.named_routes.names
    end
  end

  def storage_app(dir, service)
    active_storage = Object.new
    active_storage.define_singleton_method(:service) { service }
    config = Object.new
    config.define_singleton_method(:active_storage) { active_storage }
    app = Object.new
    app.define_singleton_method(:root) { Pathname(dir) }
    app.define_singleton_method(:config) { config }
    app
  end
end
