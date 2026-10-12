# frozen_string_literal: true

require "test_helper"
require "yaml"
require "i18n"

class LocalesTest < Minitest::Test
  # rubocop:disable Style/FormatStringToken -- I18n interpolation tokens match en.yml
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
    "collection.saved" => "Saved",
    "collection.drag" => "Drag",
    "collection.images_aria" => "Images",
    "collection.edit_aria" => "Edit %{name}",
    "collection.view_aria" => "View %{name}",
    "collection.image_fallback_title" => "Image",
    "collection.image_fallback" => "IMAGE",
    "collection.image_name_fallback" => "image",
    "collection.file_fallback" => "FILE",
    "collection.trash" => "Trash",
    "collection.remove_from_here" => "Remove from here",
    "collection.fields.caption" => "Caption",
    "collection.fields.credit" => "Credit",
    "collection.fields.alt_text" => "Alt text",
    "collection.fields.name" => "Name",
    "collection.fields.description" => "Description",
    "collection.empty_messages.images" => "No images yet.",
    "collection.empty_messages.files" => "No files yet.",
    "collection.empty_messages.attachments" => "Nothing here yet.",
    "collection.empty_messages.placements" => "Pull one from a library or drop a new one in.",
    "collection.displays.list" => "List",
    "collection.displays.carousel" => "Slides",
    "collection.displays.grid" => "Grid",
    "collection.stale_form" => "This form is out of date. Reload the page and try again.",
    "collection.gone" => "One of these is gone. Reload the page and try again.",
    "picker.upload" => "Upload",
    "picker.upload_from_device" => "Upload from device",
    "picker.search_placeholder" => "Search",
    "picker.progress" => "Progress",
    "picker.select_images" => "Select one or more images",
    "picker.select_one_or_more" => "Select one or more",
    "picker.clear" => "Clear",
    "picker.add_selected" => "Add selected",
    "flashes.attachment_removed" => "Attachment removed.",
    "flashes.attachment_restored" => "Attachment restored.",
    "flashes.saved" => "Saved.",
    "flashes.saved_short" => "Saved",
    "flashes.file_updated" => "File updated",
    "flashes.could_not_save" => "Could not save.",
    "flashes.attachment_resource_not_found" => "Attachment resource not found",
    "flashes.not_found" => "Not found",
    "errors.content_type_not_allowed" => "is not allowed",
    "errors.attachment_kind_not_enabled" => "is not enabled",
    "file_facts.types.image/jpeg" => "JPEG",
    "file_facts.types.image/png" => "PNG",
    "file_facts.types.application/pdf" => "PDF",
    "google_drive.connect" => "Connect Google Drive",
    "google_drive.search" => "Search",
    "google_drive.disconnect" => "Disconnect",
    "google_drive.import_selected" => "Import selected",
    "google_drive.back_to_upload" => "Back to upload page",
    "google_drive.empty" => "No Google Drive files matched the current search.",
    "google_drive.next_page" => "Next page",
    "google_drive.title" => "Google Drive",
    "google_drive.connected" => "Connected Google Drive.",
    "google_drive.disconnected" => "Disconnected Google Drive.",
    "google_drive.session_expired" => "Google Drive session expired. Reconnect to continue.",
    "google_drive.not_enabled" => "Google Drive addon is not enabled",
    "type_labels.placement.title" => "Image",
    "libraries.keys.default" => "Images"
  }.freeze
  # rubocop:enable Style/FormatStringToken

  def setup
    @previous_load_path = I18n.load_path.dup
    @previous_backend = I18n.backend
    @previous_locale = I18n.locale
    I18n.backend = I18n::Backend::Simple.new
    I18n.backend.load_translations(*Dir[File.join(engine_locales_dir, "*.yml")])
    I18n.locale = :en
  end

  def teardown
    I18n.backend = @previous_backend
    I18n.locale = @previous_locale
    assert_equal @previous_load_path, I18n.load_path,
                 "locales tests must not mutate I18n.load_path"
  end

  def test_engine_ships_only_english_locale_files
    files = Dir[File.join(engine_locales_dir, "*")].map { |path| File.basename(path) }

    assert_equal ["en.yml", "recording_studio_attachable.en.yml"], files.sort
  end

  def test_engine_exposes_english_locale_paths
    locale_path = File.expand_path(File.join(engine_locales_dir, "en.yml"))
    existent = RecordingStudioAttachable::Engine.paths["config/locales"].existent.map { |path| File.expand_path(path) }

    assert_includes existent, locale_path
  end

  def test_lib_sources_do_not_append_i18n_load_path
    lib_root = File.expand_path("../lib", __dir__)
    ruby_files = Dir[File.join(lib_root, "**", "*.rb")]

    refute_empty ruby_files, "expected lib/**/*.rb files to scan"

    ruby_files.each do |path|
      source = File.read(path)

      refute_includes source, "i18n.load_path", "#{path} must not touch i18n.load_path"
      refute_includes source, "I18n.load_path", "#{path} must not touch I18n.load_path"
    end
  end

  def test_english_attachable_keys_resolve_without_missing_translations
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

  def test_mime_type_locale_keys_resolve_without_default
    assert_equal "JPEG", I18n.t("recording_studio.attachable.file_facts.types.image/jpeg", raise: true)
    assert_equal "PNG", I18n.t("recording_studio.attachable.file_facts.types.image/png", raise: true)
    assert_equal "PDF", I18n.t("recording_studio.attachable.file_facts.types.application/pdf", raise: true)
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
    assert tree.key?("flashes")
    assert tree.key?("errors")
    assert tree.key?("file_facts")
    assert tree.key?("js")
  end

  def test_legacy_top_level_locale_file_is_unchanged_for_existing_callers
    tree = locale_tree(File.join(engine_locales_dir, "recording_studio_attachable.en.yml"), "en")
           .fetch("recording_studio_attachable")

    assert_equal "Images", tree.dig("libraries", "keys", "default")
    assert_equal "Add from library", tree.dig("placements", "add")
    assert_equal "Saved", tree.dig("attachments", "updated")
    assert_equal "File updated", tree.dig("attachment_file_buttons", "updated")
  end

  def test_copy_legacy_t_prefers_legacy_override
    with_isolated_backend do
      I18n.backend.store_translations(
        :en,
        {
          "recording_studio_attachable" => { "google_drive" => { "connected" => "LEGACY Connected" } },
          "recording_studio" => { "attachable" => { "google_drive" => { "connected" => "NESTED Connected" } } }
        }
      )

      assert_equal "LEGACY Connected",
                   RecordingStudioAttachable::Copy.legacy_t(
                     "google_drive.connected",
                     "google_drive.connected",
                     default: "Connected Google Drive."
                   )
    end
  end

  def test_copy_legacy_t_falls_back_to_nested_when_legacy_missing
    with_isolated_backend do
      I18n.backend.store_translations(
        :en,
        { "recording_studio" => { "attachable" => { "google_drive" => { "connected" => "NESTED Connected" } } } }
      )

      assert_equal "NESTED Connected",
                   RecordingStudioAttachable::Copy.legacy_t(
                     "google_drive.connected",
                     "google_drive.connected",
                     default: "Connected Google Drive."
                   )
    end
  end

  def test_gemspec_does_not_depend_on_internationalization
    gemspec = File.read(File.expand_path("../recording_studio_attachable.gemspec", __dir__))

    refute_includes gemspec, "recording_studio_internationalization"
  end

  private

  def engine_locales_dir
    File.expand_path("../config/locales", __dir__)
  end

  def locale_tree(path, locale)
    YAML.safe_load_file(path, aliases: true).fetch(locale)
  end

  def with_isolated_backend
    previous_backend = I18n.backend
    previous_load_path = I18n.load_path.dup
    I18n.backend = I18n::Backend::Simple.new
    yield
  ensure
    I18n.backend = previous_backend
    assert_equal previous_load_path, I18n.load_path,
                 "with_isolated_backend must not mutate I18n.load_path"
  end
end
