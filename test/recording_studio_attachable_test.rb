# frozen_string_literal: true

require "test_helper"

class RecordingStudioAttachableTest < Minitest::Test
  def test_version_exists
    refute_nil RecordingStudioAttachable::VERSION
  end

  def test_engine_exists
    assert_kind_of Class, RecordingStudioAttachable::Engine
  end

  def test_upload_view_uses_flatpack_components
    view_path = File.expand_path("../app/views/recording_studio_attachable/attachment_uploads/new.html.erb", __dir__)
    view_source = File.read(view_path)

    assert_includes view_source, "FlatPack::PageTitle::Component"
    assert_includes view_source, "FlatPack::Alert::Component"
    assert_includes view_source, "FlatPack::Card::Component"
    assert_includes view_source, "FlatPack::Button::Component"
  end

  def test_listing_view_includes_scope_and_kind_filters
    view_path = File.expand_path("../app/views/recording_studio_attachable/recording_attachments/index.html.erb", __dir__)
    view_source = File.read(view_path)

    assert_includes view_source, "Direct"
    assert_includes view_source, "Subtree"
    assert_includes view_source, "Images"
    assert_includes view_source, "Files"
  end
end
