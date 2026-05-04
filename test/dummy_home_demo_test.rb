# frozen_string_literal: true

require "test_helper"

class DummyHomeDemoTest < Minitest::Test
  def test_dummy_home_page_has_root_and_page_demo_actions
    home_view = File.read(File.expand_path("../dummy/app/views/home/index.html.erb", __dir__))

    assert_includes home_view, 'title: "Attachment demo"'
    assert_includes home_view, 'subtitle: "Upload images and files"'
    assert_includes home_view, 'text: "Library"'
    assert_includes home_view, 'title: "Page attachments"'
    assert_includes home_view, 'text: "Attachments"'
  end

  def test_dummy_home_controller_builds_root_and_page_attachment_paths
    home_controller = File.read(File.expand_path("../dummy/app/controllers/home_controller.rb", __dir__))

    assert_includes home_controller, "@page = Page.first"
    assert_includes home_controller, "@page_recording = RecordingStudio::Recording.unscoped.find_by("
    assert_includes home_controller, "@root_attachment_listing_path = attachment_listing_path(@root_recording, scope: :subtree, kind: :all)"
    assert_includes home_controller, '@page_attachment_upload_path = attachment_upload_path(@page_recording)'
  end

  def test_dummy_page_recordable_is_registered_seeded_and_migrated
    page_model = File.read(File.expand_path("../dummy/app/models/page.rb", __dir__))
    recording_studio_initializer = File.read(File.expand_path("../dummy/config/initializers/recording_studio.rb", __dir__))
    seeds = File.read(File.expand_path("../dummy/db/seeds.rb", __dir__))
    schema = File.read(File.expand_path("../dummy/db/schema.rb", __dir__))

    assert_includes page_model, "class Page < ApplicationRecord"
    assert_includes page_model, "RecordingStudio::Capabilities::Attachable"
    assert_includes recording_studio_initializer, '"Workspace", "Page", "RecordingStudioAttachable::Attachment"'
    assert_includes seeds, 'page = Page.find_or_create_by!(title: "Home page")'
    assert_includes seeds, "recordable: page"
    assert_includes schema, 'create_table "pages"'
    assert_includes schema, 't.string "title"'
  end

  def test_attachment_listing_uses_card_grid_for_non_file_filters
    listing_view = File.read(File.expand_path("../app/views/recording_studio_attachable/recording_attachments/index.html.erb", __dir__))

    assert_includes listing_view, "@kind.to_sym != :files"
    assert_includes listing_view, "attachment.previewable? && attachment.file.attached?"
    assert_includes listing_view, 'text: "Download"'
  end
end
