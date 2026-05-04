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
    assert_includes view_source, "rails_direct_uploads_path"
    assert_includes view_source, "max-files-count-value"
  end

  def test_listing_view_includes_search_bulk_remove_and_pagination_controls
    view_path = File.expand_path("../app/views/recording_studio_attachable/recording_attachments/index.html.erb", __dir__)
    view_source = File.read(view_path)

    assert_includes view_source, "Direct"
    assert_includes view_source, "Subtree"
    assert_includes view_source, "Images"
    assert_includes view_source, "Files"
    assert_includes view_source, "Search by attachment name"
    assert_includes view_source, "Bulk remove selected"
    assert_includes view_source, "Previous"
    assert_includes view_source, "Next"
    assert_includes view_source, "image_tag attachment.file"
  end

  def test_attachment_show_view_uses_direct_upload_file_field_and_hides_internal_ids
    view_path = File.expand_path("../app/views/recording_studio_attachable/attachments/show.html.erb", __dir__)
    view_source = File.read(view_path)

    assert_includes view_source, 'file_field_tag "attachment[signed_blob_id]"'
    refute_includes view_source, "Recording id"
    refute_includes view_source, "Parent recording id"
  end
end
