# frozen_string_literal: true

require "test_helper"

class DummyDocsTest < Minitest::Test
  def test_dummy_routes_expose_sidebar_docs_pages
    routes_source = File.read(File.expand_path("../dummy/config/routes.rb", __dir__))

    assert_includes routes_source, 'get "setup", to: "docs#setup"'
    assert_includes routes_source, 'get "config", to: "docs#configuration"'
    assert_includes routes_source, 'get "methods", to: "docs#methods_reference"'
    assert_includes routes_source, 'get "gem_views", to: "docs#gem_views"'
  end

  def test_dummy_sidebar_links_to_docs_pages
    sidebar_source = File.read(File.expand_path("../dummy/app/views/layouts/flat_pack/_sidebar.html.erb", __dir__))

    assert_includes sidebar_source, 'label: "Setup"'
    assert_includes sidebar_source, "setup_docs_path"
    assert_includes sidebar_source, 'label: "Config"'
    assert_includes sidebar_source, "configuration_docs_path"
    assert_includes sidebar_source, 'label: "Methods"'
    assert_includes sidebar_source, "methods_docs_path"
    assert_includes sidebar_source, 'label: "Gem views"'
    assert_includes sidebar_source, "gem_views_docs_path"
  end

  def test_dummy_config_page_mentions_layout_override
    config_source = File.read(File.expand_path("../dummy/app/views/docs/configuration.html.erb", __dir__))
    controller_source = File.read(File.expand_path("../dummy/app/controllers/docs_controller.rb", __dir__))

    assert_includes config_source, "FlatPack::CodeBlock::Component"
    assert_includes controller_source, "config.layout = :blank"
    assert_includes controller_source, 'host app layout like "application"'
  end
end
