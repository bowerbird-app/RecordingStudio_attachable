# frozen_string_literal: true

require "test_helper"

class DummyDocsTest < Minitest::Test
  def test_dummy_routes_expose_sidebar_docs_pages
    routes_source = File.read(File.expand_path("dummy/config/routes.rb", __dir__))

    assert_includes routes_source, 'get "setup", to: "docs#setup"'
    assert_includes routes_source, 'get "config", to: "docs#configuration"'
    assert_includes routes_source, 'get "methods", to: "docs#methods_reference"'
    assert_includes routes_source, 'get "plugins", to: "docs#plugins"'
    assert_includes routes_source, 'get "gem_views", to: "docs#gem_views"'
    assert_includes routes_source, 'get "recordables", to: "docs#recordables"'
    assert_includes routes_source, 'get "query", to: "docs#query"'
  end

  def test_dummy_sidebar_links_to_docs_pages
    sidebar_source = File.read(File.expand_path("dummy/app/views/layouts/flat_pack/_sidebar.html.erb", __dir__))

    assert_includes sidebar_source, 'label: "Setup"'
    assert_includes sidebar_source, "setup_docs_path"
    assert_includes sidebar_source, 'label: "Config"'
    assert_includes sidebar_source, "configuration_docs_path"
    assert_includes sidebar_source, 'label: "Methods"'
    assert_includes sidebar_source, "methods_docs_path"
    assert_includes sidebar_source, 'label: "Plugins"'
    assert_includes sidebar_source, "plugins_docs_path"
    assert_includes sidebar_source, 'label: "Gem views"'
    assert_includes sidebar_source, "gem_views_docs_path"
    assert_includes sidebar_source, 'label: "Recordables"'
    assert_includes sidebar_source, "recordables_docs_path"
    assert_includes sidebar_source, 'label: "Query"'
    assert_includes sidebar_source, "query_docs_path"
    assert_match(/label: "Config"[\s\S]*icon: :settings/, sidebar_source)
    assert_match(/label: "Plugins"[\s\S]*icon: :box/, sidebar_source)
    assert_match(/label: "Gem views"[\s\S]*icon: :file/, sidebar_source)
    assert_match(/label: "Recordables"[\s\S]*icon: :folder/, sidebar_source)
    assert_match(/label: "Query"[\s\S]*icon: :file/, sidebar_source)
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

  def test_dummy_plugins_page_documents_provider_apis
    plugins_source = File.read(File.expand_path("dummy/app/views/docs/plugins.html.erb", __dir__))
    controller_source = File.read(File.expand_path("dummy/app/controllers/docs_controller.rb", __dir__))

    assert_includes plugins_source, 'title: "Plugins"'
    assert_includes plugins_source, "FlatPack::SectionTitle::Component"
    assert_includes plugins_source, "FlatPack::CodeBlock::Component"
    assert_includes plugins_source, "FlatPack::List::Component"
    assert_includes controller_source, "def plugins"
    assert_includes controller_source, "config.register_upload_provider("
    assert_includes controller_source, "RecordingStudioAttachable::Services::ImportAttachment.call"
    assert_includes controller_source, "recording_attachment_imports_path(recording)"
    assert_includes controller_source, "route_helpers.google_drive_imports_path(recording_id: recording.id)"
    assert_includes controller_source, "signed_blob_id: blob.signed_id"
    assert_includes controller_source,
                    "The built-in Google Drive addon in the dummy app demonstrates the same provider registration and import flow"
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

  def test_dummy_recordables_page_lists_recordable_type_counts
    recordables_source = File.read(File.expand_path("dummy/app/views/docs/recordables.html.erb", __dir__))
    controller_source = File.read(File.expand_path("dummy/app/controllers/docs_controller.rb", __dir__))

    assert_includes recordables_source, 'title: "Recordable types"'
    assert_includes recordables_source, "FlatPack::List::Component"
    assert_includes recordables_source, "pluralize(recordable_type[:recordings_count], \"recording\")"
    assert_includes recordables_source, "pluralize(recordable_type[:recordables_count], \"recordable record\")"
    assert_includes controller_source, "def recordables"
    assert_includes controller_source, "RecordingStudio::Recording.unscoped.where(recordable_type: recordable_type).count"
    assert_includes controller_source, "model.unscoped.count"
  end

  def test_dummy_query_page_documents_parent_recording_lookup
    query_source = File.read(File.expand_path("dummy/app/views/docs/query.html.erb", __dir__))
    controller_source = File.read(File.expand_path("dummy/app/controllers/docs_controller.rb", __dir__))

    assert_includes query_source, 'title: "Query"'
    assert_includes query_source, 'title: "Any recordable type with images"'
    assert_includes query_source, "FlatPack::SectionTitle::Component"
    assert_includes query_source, "FlatPack::CodeBlock::Component"
    assert_includes controller_source, "def query"
    assert_includes controller_source, "RecordingStudioAttachable::Queries::WithAttachments.new"
    assert_includes controller_source, 'target_recordable_type = "Page"'
    assert_includes controller_source, "recordable_type: target_recordable_type"
    assert_includes controller_source, "kind: :images"
    assert_includes controller_source, "target_recordable_type.constantize.where"
    assert_includes controller_source, "id: recordings_with_images.select(:recordable_id)"
  end
end
