# frozen_string_literal: true

require "test_helper"

class DummyDocsTest < Minitest::Test
  def test_dummy_routes_expose_sidebar_docs_pages
    routes_source = File.read(File.expand_path("dummy/config/routes.rb", __dir__))

    assert_includes routes_source, 'get "setup", to: "docs#setup"'
    assert_includes routes_source, 'get "config", to: "docs#configuration"'
    assert_includes routes_source, 'get "methods", to: "docs#methods_reference"'
    assert_includes routes_source, 'get "gem_views", to: "docs#gem_views"'
  end

  def test_dummy_sidebar_links_to_docs_pages
    sidebar_source = File.read(File.expand_path("dummy/app/views/layouts/flat_pack/_sidebar.html.erb", __dir__))

    assert_includes sidebar_source, 'label: "Setup"'
    assert_includes sidebar_source, "setup_docs_path"
    assert_includes sidebar_source, 'label: "Config"'
    assert_includes sidebar_source, "configuration_docs_path"
    assert_includes sidebar_source, 'label: "Methods"'
    assert_includes sidebar_source, "methods_docs_path"
    assert_includes sidebar_source, 'label: "Gem views"'
    assert_includes sidebar_source, "gem_views_docs_path"
    assert_match(/label: "Config"[\s\S]*icon: :settings/, sidebar_source)
    assert_match(/label: "Gem views"[\s\S]*icon: :file/, sidebar_source)
  end

  def test_dummy_config_page_mentions_layout_override
    config_source = File.read(File.expand_path("dummy/app/views/docs/configuration.html.erb", __dir__))
    controller_source = File.read(File.expand_path("dummy/app/controllers/docs_controller.rb", __dir__))

    assert_includes config_source, "FlatPack::CodeBlock::Component"
    assert_includes controller_source, "config.layout = :blank"
    assert_includes controller_source, 'host app layout like "application"'
    assert_includes controller_source, "Browse the attachment library and manage uploads with bulk remove actions."
  end

  def test_dummy_methods_page_uses_library_and_upload_labels
    controller_source = File.read(File.expand_path("dummy/app/controllers/docs_controller.rb", __dir__))

    assert_includes controller_source, 'title: "Library path"'
    assert_includes controller_source, 'title: "Upload path"'
  end

  def test_dummy_setup_page_covers_active_storage_and_install_flow
    setup_source = File.read(File.expand_path("dummy/app/views/docs/setup.html.erb", __dir__))
    controller_source = File.read(File.expand_path("dummy/app/controllers/docs_controller.rb", __dir__))

    assert_includes setup_source, "Prerequisites"
    assert_includes setup_source, "Verify Active Storage wiring"
    assert_includes setup_source, "FlatPack::CodeBlock::Component"
    assert_includes controller_source, "bin/rails active_storage:install"
    assert_includes controller_source, "generate recording_studio_attachable:install"
    assert_includes controller_source, 'config.recordable_types << "RecordingStudioAttachable::Attachment"'
    assert_includes controller_source, "ActiveStorage.start()"
  end

  def test_dummy_gem_views_page_lists_the_gem_ui_surfaces
    gem_views_source = File.read(File.expand_path("dummy/app/views/docs/gem_views.html.erb", __dir__))
    controller_source = File.read(File.expand_path("dummy/app/controllers/docs_controller.rb", __dir__))

    assert_includes gem_views_source, "FlatPack::List::Component"
    assert_includes gem_views_source, "FlatPack::List::Item.new"
    assert_includes controller_source, 'title: "Media library"'
    assert_includes controller_source, 'title: "Upload attachments"'
    assert_includes controller_source, 'title: "Attachment details"'
    assert_includes controller_source, 'title: "Blank layout"'
    assert_includes controller_source, "Upload images and files"
    assert_includes controller_source, "Browse the attachment library and manage uploads with bulk remove actions."
  end
end
