# frozen_string_literal: true

require "test_helper"

class AttachmentBrowserViewsTest < Minitest::Test
  def test_attachment_show_edits_caption_credit_and_alt
    source = File.read(File.expand_path("../app/views/recording_studio_attachable/attachments/show.html.erb", __dir__))

    assert_includes source, 'name: "attachment[caption]"'
    assert_includes source, 'name: "attachment[credit]"'
    assert_includes source, 'name: "attachment[alt_text]"'
    assert_includes source, 'class: "w-full flex-col"'
    assert_includes source, "place_labels"
    assert_includes source, "used_in"
    assert_includes source, "trash_in_use"
    refute_includes source, "Placements"
  end

  def test_locales_avoid_backend_words
    source = File.read(File.expand_path("../config/locales/recording_studio_attachable.en.yml", __dir__))
    nested = File.read(File.expand_path("../config/locales/en.yml", __dir__))

    refute_includes source, "recordable"
    refute_includes source, "capability"
    refute_includes source, "Recordable"
    refute_includes nested, "recordable"
    refute_includes nested, "capability"
  end

  def test_attachment_index_uses_nested_attachable_i18n_keys
    source = File.read(File.expand_path("../app/views/recording_studio_attachable/recording_attachments/index.html.erb", __dir__))

    assert_includes source, 't("recording_studio.attachable.library.title")'
    assert_includes source, 't("recording_studio.attachable.library.upload")'
    assert_includes source, 't("recording_studio.attachable.library.empty_title")'
    assert_includes source, 't("recording_studio.attachable.navigation.back")'
  end

  def test_routes_do_not_mount_libraries_or_placements
    routes = File.read(File.expand_path("../config/routes.rb", __dir__))

    refute_includes routes, "libraries"
    refute_includes routes, "placements"
  end
end
