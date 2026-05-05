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
    upload_controller_source = File.read(
      File.expand_path("../app/javascript/controllers/recording_studio_attachable/upload_controller.js", __dir__)
    )

    assert_includes view_source, "FlatPack::Breadcrumb::Component"
    assert_includes view_source, 'items: [{ text: "Home", href: main_app.root_path, icon: "home" }]'
    assert_includes view_source, "FlatPack::PageTitle::Component"
    assert_includes view_source, "FlatPack::Button::Component"
    assert_includes view_source, "rails_direct_uploads_path"
    assert_includes view_source, "max-files-count-value"
    assert_includes view_source, 'title: "Upload"'
    assert_includes view_source, "Allowed file types:"
    assert_includes view_source, "Drag and drop, or choose"
    assert_includes view_source, 'data: { action: "recording-studio-attachable--upload#browse" }'
    assert_includes view_source, '"recording-studio-attachable--upload-target": "finalizeButton"'
    assert_includes upload_controller_source, 'credentials: "same-origin"'
    assert_includes upload_controller_source, '"X-CSRF-Token": document.querySelector("meta[name=\'csrf-token\']")?.content || ""'
    refute_includes view_source, '<button type="button" data-action="recording-studio-attachable--upload#browse"'
    refute_includes view_source, '<button type="button" data-recording-studio-attachable--upload-target="finalizeButton"'
    refute_includes view_source, "FlatPack::Card::Component"
    refute_includes view_source, 'title: "Drop files here"'
    refute_includes view_source, "Multiple uploads, previews, and direct-upload progress are handled in-page."
    refute_includes view_source, "Drag files anywhere into this zone or browse from disk."
    refute_includes view_source, "Upload rules"
    refute_includes view_source, 'title: "Queue"'
  end

  def test_listing_view_keeps_upload_bulk_remove_and_pagination_controls_without_filter_ui
    view_path = File.expand_path("../app/views/recording_studio_attachable/recording_attachments/index.html.erb", __dir__)
    view_source = File.read(view_path)

    assert_includes view_source, "FlatPack::Breadcrumb::Component"
    assert_includes view_source, 'items: [{ text: "Home", href: main_app.root_path, icon: "home" }]'
    assert_includes view_source, 'title: "Library"'
    assert_includes view_source, 'text: "Upload files"'
    assert_includes view_source, "Bulk remove selected"
    assert_includes view_source, "Previous"
    assert_includes view_source, "Next"
    assert_includes view_source, "image_tag attachment.file"
    assert_includes view_source, "Nothing uplaoded yet"
    refute_includes view_source, "Scope:"
    refute_includes view_source, "Kind:"
    refute_includes view_source, "Search by attachment name"
    refute_match(/FlatPack::Badge::Component\.new\([^\n]+style:\s*:secondary/, view_source)
  end

  def test_attachment_show_view_uses_direct_upload_file_field_and_hides_internal_ids
    view_path = File.expand_path("../app/views/recording_studio_attachable/attachments/show.html.erb", __dir__)
    view_source = File.read(view_path)

    assert_includes view_source, 'file_field_tag "attachment[signed_blob_id]"'
    refute_includes view_source, "Recording id"
    refute_includes view_source, "Parent recording id"
  end
end
