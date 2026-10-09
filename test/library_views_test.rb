# frozen_string_literal: true

require "test_helper"
require_relative "../app/helpers/recording_studio_attachable/application_helper"

class LibraryViewsTest < Minitest::Test
  def test_attachment_show_edits_caption_credit_and_alt
    source = File.read(File.expand_path("../app/views/recording_studio_attachable/attachments/show.html.erb", __dir__))

    assert_includes source, 'name: "attachment[caption]"'
    assert_includes source, 'name: "attachment[credit]"'
    assert_includes source, 'name: "attachment[alt_text]"'
    assert_includes source, "placement_usages"
    assert_includes source, "used_in"
    assert_includes source, "trash_in_use"
  end

  def test_placements_index_reuses_the_library_picker
    source = File.read(File.expand_path("../app/views/recording_studio_attachable/placements/index.html.erb", __dir__))

    assert_includes source, "recording-studio-attachable--attachment-image-picker"
    assert_includes source, "recording_attachment_picker_path(@library)"
    assert_includes source, "recording_attachments_path(@library)"
    assert_includes source, 'text: t("recording_studio_attachable.placements.add")'
    assert_includes source, 'text: t("recording_studio_attachable.placements.upload")'
    assert_includes source, "attachment_image_pickers/modal"
    refute_includes source, "recordable"
    refute_includes source, "Recordable"
  end

  def test_library_and_placement_models_declare_product_labels
    library = File.read(File.expand_path("../app/models/recording_studio_attachable/library.rb", __dir__))
    placement = File.read(File.expand_path("../app/models/recording_studio_attachable/placement.rb", __dir__))

    assert_includes library, 'label: "Image library"'
    refute_includes library, "allowed_parent_types:"
    assert_includes placement, 'label: "Image"'
    refute_includes placement, "allowed_parent_types:"
    refute_includes library, "Recordable"
    refute_includes placement, "Recordable"
  end

  def test_locales_avoid_backend_words
    source = File.read(File.expand_path("../config/locales/recording_studio_attachable.en.yml", __dir__))

    refute_includes source, "recordable"
    refute_includes source, "capability"
    refute_includes source, "Recordable"
  end

  def test_library_placement_controller_submits_the_picked_image
    source = File.read(
      File.expand_path("../app/javascript/controllers/recording_studio_attachable/library_placement_controller.js", __dir__)
    )

    assert_includes source, 'static targets = ["form", "attachmentId"]'
    assert_includes source, "addFromLibrary(event)"
    assert_includes source, "this.formTarget.requestSubmit()"
    assert_includes source, "browseUpload(event)"
    assert_includes source, 'form?.querySelector("input[type=file]")'
  end

  def test_helper_reorders_placement_ids
    helper = Object.new
    helper.extend(RecordingStudioAttachable::ApplicationHelper)
    first = Struct.new(:placement_recording).new(Struct.new(:id).new("place-1"))
    second = Struct.new(:placement_recording).new(Struct.new(:id).new("place-2"))
    resolved = [first, second]

    assert_equal %w[place-2 place-1], helper.move_placement_ids(resolved, 0, 1)
    assert_equal %w[place-1 place-2], helper.move_placement_ids(resolved, 0, -1)
  end
end
