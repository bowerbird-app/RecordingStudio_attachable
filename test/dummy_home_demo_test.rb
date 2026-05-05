# frozen_string_literal: true

require "test_helper"

class DummyHomeDemoTest < Minitest::Test
  def test_dummy_home_page_has_root_and_page_demo_actions
    home_view = File.read(File.expand_path("dummy/app/views/home/index.html.erb", __dir__))

    assert_includes home_view, 'title: "Attachment demo"'
    assert_includes home_view, 'subtitle: "Workspace uploads accept images and files. Page uploads accept images only."'
    assert_includes home_view, 'title: "Workspace attachments"'
    assert_includes home_view, 'subtitle: "Upload images, PDFs, and text files to the workspace library."'
    assert_includes home_view, 'title: "Workspace attachments",'
    assert_includes home_view, 'anchor_link: true'
    assert_includes home_view, 'text: "Library"'
    assert_includes home_view, 'title: "Page attachments"'
    assert_includes home_view, 'text: "Attachments"'
  end

  def test_dummy_home_controller_builds_root_and_page_attachment_paths
    home_controller = File.read(File.expand_path("dummy/app/controllers/home_controller.rb", __dir__))

    assert_includes home_controller, "@page = Page.first"
    assert_includes home_controller, "@page_recording = RecordingStudio::Recording.unscoped.find_by("
    assert_includes home_controller, "@root_attachment_listing_path = attachment_listing_path(@root_recording, scope: :subtree, kind: :all)"
    assert_includes home_controller, "@page_attachment_upload_path = attachment_upload_path(@page_recording)"
  end

  def test_dummy_page_recordable_is_registered_seeded_and_migrated
    page_model = File.read(File.expand_path("dummy/app/models/page.rb", __dir__))
    workspace_model = File.read(File.expand_path("dummy/app/models/workspace.rb", __dir__))
    recording_studio_initializer = File.read(File.expand_path("dummy/config/initializers/recording_studio.rb", __dir__))
    seeds = File.read(File.expand_path("dummy/db/seeds.rb", __dir__))
    schema = File.read(File.expand_path("dummy/db/schema.rb", __dir__))

    assert_includes page_model, "class Page < ApplicationRecord"
    assert_includes page_model, "RecordingStudio::Capabilities::Attachable"
    assert_includes page_model, 'allowed_content_types: [ "image/*" ]'
    assert_includes page_model, 'enabled_attachment_kinds: %i[ image ]'
    assert_includes workspace_model, 'allowed_content_types: [ "image/*", "application/pdf", "text/plain" ]'
    assert_includes workspace_model, 'enabled_attachment_kinds: %i[ image file ]'
    assert_includes recording_studio_initializer, '"Workspace", "Page", "RecordingStudioAttachable::Attachment"'
    assert_includes seeds, 'page = Page.find_or_create_by!(title: "Home page")'
    assert_includes seeds, "recordable: page"
    assert_includes schema, 'create_table "pages"'
    assert_includes schema, 'create_table "recording_studio_attachable_attachments"'
    assert_includes schema, 't.string "title"'
  end

  def test_attachment_listing_uses_card_grid_with_empty_state_when_no_results_exist
    listing_view = File.read(File.expand_path("../app/views/recording_studio_attachable/recording_attachments/index.html.erb", __dir__))

    assert_includes listing_view, "FlatPack::Breadcrumb::Component"
    assert_includes listing_view, 'items: [{ text: "Home", href: main_app.root_path, icon: "home" }]'
    assert_includes listing_view, 'title: "Library"'
    assert_includes listing_view, "@kind.to_sym != :files"
    assert_includes listing_view, 'text: "Upload files"'
    assert_includes listing_view, "Bulk remove selected"
    assert_includes listing_view, "attachment_ids[]"
    assert_includes listing_view, "attachment.previewable? && attachment.file.attached?"
    assert_includes listing_view, 'text: "Download"'
    assert_includes listing_view, "Nothing uplaoded yet"
    refute_includes listing_view, 'title: "Filters"'
    refute_includes listing_view, 'title: "Search"'
  end

  def test_dummy_layouts_reference_propshaft_resolvable_css_assets
    application_layout = File.read(File.expand_path("dummy/app/views/layouts/application.html.erb", __dir__))
    sidebar_layout = File.read(File.expand_path("dummy/app/views/layouts/flat_pack_sidebar.html.erb", __dir__))
    blank_layout = File.read(File.expand_path("../app/views/layouts/recording_studio_attachable/blank.html.erb", __dir__))

    [application_layout, sidebar_layout, blank_layout].each do |layout|
      assert_includes layout, 'stylesheet_link_tag "application.css"'
      assert_includes layout, 'stylesheet_link_tag "flat_pack/variables"'
      assert_includes layout, 'stylesheet_link_tag "flat_pack/rich_text"'
      assert_includes layout, 'stylesheet_link_tag "tailwind.css"'
    end
  end

  def test_dummy_javascript_boot_enables_turbo_drive_and_active_storage
    importmap = File.read(File.expand_path("dummy/config/importmap.rb", __dir__))
    application_js = File.read(File.expand_path("dummy/app/javascript/application.js", __dir__))

    assert_includes importmap, 'pin "@hotwired/turbo-rails", to: "turbo.min.js"'
    assert_includes application_js, 'import "@hotwired/turbo-rails"'
    assert_includes application_js, 'import * as ActiveStorage from "@rails/activestorage"'
    assert_includes application_js, 'ActiveStorage.start()'
  end

  def test_dummy_schema_includes_active_storage_tables_for_direct_uploads
    schema = File.read(File.expand_path("dummy/db/schema.rb", __dir__))

    assert_includes schema, 'create_table "active_storage_blobs"'
    assert_includes schema, 'create_table "active_storage_attachments"'
    assert_includes schema, 'create_table "active_storage_variant_records"'
    assert_includes schema, 'idx_rs_attachable_parent_active'
    assert_includes schema, 'idx_rs_attachable_root_active'
  end

  def test_dummy_sidebar_links_to_the_recording_tree_demo_instead_of_recording_studio_root
    sidebar_partial = File.read(File.expand_path("dummy/app/views/layouts/flat_pack/_sidebar.html.erb", __dir__))
    routes = File.read(File.expand_path("dummy/config/routes.rb", __dir__))
    tree_controller = File.read(File.expand_path("dummy/app/controllers/recording_trees_controller.rb", __dir__))
    tree_view = File.read(File.expand_path("dummy/app/views/recording_trees/index.html.erb", __dir__))
    tree_node_partial = File.read(File.expand_path("dummy/app/views/recording_trees/_recording_node.html.erb", __dir__))

    refute_includes sidebar_partial, 'href: "/recording_studio"'
    assert_includes sidebar_partial, 'label: "Recording tree"'
    assert_includes sidebar_partial, "href: recording_tree_path"
    assert_includes routes, 'get "recording_tree", to: "recording_trees#index", as: :recording_tree'
    assert_includes tree_controller, "RecordingStudio::Recording.unscoped.includes(:recordable).order(:created_at).to_a"
    assert_includes tree_view, 'title: "Recording tree"'
    assert_includes tree_view, 'render partial: "recording_node", collection: @root_recordings'
    assert_includes tree_node_partial, "recording_tree_label(recording)"
    assert_includes tree_node_partial, 'render partial: "recording_node", collection: children'
  end
end
