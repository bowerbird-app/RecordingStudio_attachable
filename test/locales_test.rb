# frozen_string_literal: true

require "test_helper"
require "yaml"

class LocalesTest < Minitest::Test
  EXPECTED_KEYS = {
    "navigation.back" => "Back",
    "navigation.return_to_source" => "Return to source page",
    "layout.title" => "Recording Studio Attachable",
    "layout.error" => "Error",
    "library.title" => "Library",
    "library.upload" => "Upload",
    "library.grid" => "Grid",
    "library.list" => "List",
    "library.view_mode" => "View mode",
    "library.search_placeholder" => "Search",
    "library.search_aria" => "Search attachments",
    "library.empty_title" => "Nothing uplaoded yet",
    "library.empty_search_title" => "Nothing found",
    "library.empty_subtitle" => "Upload files to start building this library.",
    "library.loading_more_attachments" => "Loading more attachments...",
    "library.loading_more_rows" => "Loading more rows...",
    "attachments.download" => "Download",
    "attachments.download_aria" => "Download attachment",
    "attachments.trash" => "Trash",
    "attachments.trash_aria" => "Trash attachment",
    "attachments.preview_column" => "Preview",
    "attachments.name_column" => "Name",
    "attachments.actions_column" => "Actions",
    "attachments.preview_unavailable" => "Preview unavailable",
    "attachments.image_fallback" => "IMAGE",
    "attachments.file_fallback" => "FILE",
    "attachments.name" => "Name",
    "attachments.caption" => "Caption",
    "attachments.credit" => "Credit",
    "attachments.alt_text" => "Alt text",
    "attachments.description" => "Description",
    "attachments.save" => "Save",
    "upload.title" => "Upload",
    "upload.subtitle" => "Allowed file types: %{types} · Max size: %{size}",
    "upload.type_images" => "images",
    "upload.type_pdfs" => "PDFs",
    "upload.type_text_files" => "text files",
    "upload.drag_and_drop" => "Drag and drop, or choose",
    "upload.choose_files" => "Choose files",
    "upload.progress" => "Progress",
    "upload.close" => "Close",
    "upload.remove" => "X",
    "collection.save" => "Save",
    "collection.drag" => "Drag",
    "collection.images_aria" => "Images",
    "collection.edit_aria" => "Edit %{name}",
    "collection.view_aria" => "View %{name}",
    "collection.image_fallback_title" => "Image",
    "collection.image_fallback" => "IMAGE",
    "collection.file_fallback" => "FILE",
    "collection.displays.list" => "List",
    "collection.displays.carousel" => "Slides",
    "collection.displays.grid" => "Grid",
    "picker.upload" => "Upload",
    "picker.upload_from_device" => "Upload from device",
    "picker.search_placeholder" => "Search",
    "picker.progress" => "Progress",
    "picker.select_images" => "Select one or more images",
    "picker.clear" => "Clear",
    "picker.add_selected" => "Add selected",
    "google_drive.connect" => "Connect Google Drive",
    "google_drive.search" => "Search",
    "google_drive.disconnect" => "Disconnect",
    "google_drive.import_selected" => "Import selected",
    "google_drive.back_to_upload" => "Back to upload page",
    "google_drive.empty" => "No Google Drive files matched the current search.",
    "google_drive.next_page" => "Next page",
    "google_drive.title" => "Google Drive"
  }.freeze

  def test_engine_ships_only_english_locale_files
    files = Dir[File.join(engine_locales_dir, "*")].map { |path| File.basename(path) }

    assert_equal ["en.yml", "recording_studio_attachable.en.yml"], files.sort
  end

  def test_engine_exposes_english_locale_paths
    locale_path = File.expand_path(File.join(engine_locales_dir, "en.yml"))
    existent = RecordingStudioAttachable::Engine.paths["config/locales"].existent.map { |path| File.expand_path(path) }

    assert_includes existent, locale_path
  end

  def test_english_attachable_keys_resolve_without_missing_translations
    load_attachable_locales!

    I18n.with_locale(:en) do
      EXPECTED_KEYS.each do |key, english|
        full_key = "recording_studio.attachable.#{key}"
        translation = I18n.t(full_key, default: nil)

        assert_equal english, translation, "#{full_key} should resolve to #{english.inspect}"
        assert_equal english, I18n.t(full_key, raise: true)
      end

      assert_equal(
        "Allowed file types: images · Max size: 25 MB",
        I18n.t("recording_studio.attachable.upload.subtitle", types: "images", size: "25 MB")
      )
      assert_equal "Edit Hero", I18n.t("recording_studio.attachable.collection.edit_aria", name: "Hero")
      assert_equal(
        "Import files into recording #42 using the built-in addon",
        I18n.t("recording_studio.attachable.google_drive.subtitle", recording_id: 42)
      )
    end
  end

  def test_en_yml_nests_keys_under_recording_studio_attachable
    tree = locale_tree(File.join(engine_locales_dir, "en.yml"), "en")
           .fetch("recording_studio")
           .fetch("attachable")

    assert tree.key?("navigation")
    assert tree.key?("library")
    assert tree.key?("attachments")
    assert tree.key?("upload")
    assert tree.key?("collection")
    assert tree.key?("picker")
    assert tree.key?("google_drive")
  end

  def test_legacy_top_level_locale_file_is_unchanged_for_existing_callers
    tree = locale_tree(File.join(engine_locales_dir, "recording_studio_attachable.en.yml"), "en")
           .fetch("recording_studio_attachable")

    assert_equal "Images", tree.dig("libraries", "keys", "default")
    assert_equal "Add from library", tree.dig("placements", "add")
    assert_equal "Saved", tree.dig("attachments", "updated")
  end

  private

  def engine_locales_dir
    File.expand_path("../config/locales", __dir__)
  end

  def locale_tree(path, locale)
    YAML.safe_load_file(path, aliases: true).fetch(locale)
  end

  def load_attachable_locales!
    Dir[File.join(engine_locales_dir, "*.yml")].each do |path|
      expanded = File.expand_path(path)
      I18n.load_path << expanded unless I18n.load_path.map { |entry| File.expand_path(entry) }.include?(expanded)
    end
    I18n.reload!
  end
end
