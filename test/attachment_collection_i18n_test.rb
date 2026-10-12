# frozen_string_literal: true

require "test_helper"
require "i18n"
require "recording_studio_attachable/attachment_file_facts"

class AttachmentCollectionI18nTest < Minitest::Test
  def setup
    @previous_backend = I18n.backend
    @previous_available = I18n.available_locales
    @previous_locale = I18n.locale
    I18n.available_locales = Array(I18n.available_locales) | %i[en fr]
    I18n.backend = I18n::Backend::Simple.new
    gem_locale = File.expand_path("../config/locales/en.yml", __dir__)
    I18n.backend.load_translations(gem_locale)
    I18n.locale = :en
  end

  def teardown
    I18n.backend = @previous_backend
    I18n.available_locales = @previous_available
    I18n.locale = @previous_locale
  end

  def test_empty_messages_constants_stay_english_public_api
    assert_equal "No images yet.", RecordingStudioAttachable::AttachmentCollection::EMPTY_MESSAGES.fetch(:images)
    assert_equal "Nothing here yet.", RecordingStudioAttachable::AttachmentCollection::EMPTY_MESSAGES.fetch(:attachments)
  end

  def test_empty_message_method_returns_main_literal_english
    collection = RecordingStudioAttachable::AttachmentCollection.allocate
    collection.instance_variable_set(:@association, :images)
    collection.instance_variable_set(:@empty_message, nil)

    assert_equal "No images yet.", collection.empty_message

    I18n.backend.store_translations(
      :fr,
      { recording_studio: { attachable: { collection: { empty_messages: { images: "Pas encore d'images." } } } } }
    )
    I18n.with_locale(:fr) do
      assert_equal "No images yet.", collection.empty_message
      assert_equal(
        "Pas encore d'images.",
        RecordingStudioAttachable::Copy.empty_message_for(:images, english: collection.empty_message)
      )
    end
  end

  def test_remove_label_method_returns_main_literal_english
    collection = RecordingStudioAttachable::AttachmentCollection.allocate
    collection.instance_variable_set(:@association, :attachments)
    assert_equal "Trash", collection.remove_label

    collection.instance_variable_set(:@association, :placements)
    assert_equal "Remove from here", collection.remove_label

    I18n.backend.store_translations(
      :fr,
      { recording_studio: { attachable: { collection: { trash: "Corbeille", remove_from_here: "Retirer d'ici" } } } }
    )
    I18n.with_locale(:fr) do
      collection.instance_variable_set(:@association, :attachments)
      assert_equal "Trash", collection.remove_label
      assert_equal "Corbeille", RecordingStudioAttachable::Copy.remove_label(placement: false)
      collection.instance_variable_set(:@association, :placements)
      assert_equal "Remove from here", collection.remove_label
      assert_equal "Retirer d'ici", RecordingStudioAttachable::Copy.remove_label(placement: true)
    end
  end

  def test_display_labels_constant_left_as_is
    assert_equal(
      { list: "List", carousel: "Slides", grid: "Grid" },
      RecordingStudioAttachable::AttachmentCollectionDisplay::LABELS
    )
    assert_equal "Slides", RecordingStudioAttachable::AttachmentCollectionDisplay.label(:carousel)
  end

  def test_type_label_method_returns_main_literal_english
    assert_equal "JPEG", RecordingStudioAttachable::AttachmentFileFacts::TYPE_LABELS.fetch("image/jpeg")

    attachment = Object.new
    attachment.define_singleton_method(:content_type) { "image/jpeg" }
    attachment.define_singleton_method(:respond_to?) { |name, *| name == :content_type || super(name) }
    facts = RecordingStudioAttachable::AttachmentFileFacts.new(attachment)
    assert_equal "JPEG", facts.type_label

    I18n.backend.store_translations(
      :fr,
      { recording_studio: { attachable: { file_facts: { types: { "image/jpeg" => "JPEG-FR" } } } } }
    )
    I18n.with_locale(:fr) do
      assert_equal "JPEG", facts.type_label
      assert_equal(
        "JPEG-FR",
        RecordingStudioAttachable::Copy.type_label("image/jpeg", english: facts.type_label)
      )
    end
  end

  def test_placement_title_returns_main_literal_english_at_method
    source = File.read(File.expand_path("../app/models/recording_studio_attachable/placement.rb", __dir__))
    assert_includes source, "def title"
    assert_includes source, '"Image"'
    refute_includes source, "Copy.t"
    refute_includes source, "I18n.t"

    listing = File.read(
      File.expand_path("../app/views/recording_studio_attachable/recording_attachments/index.html.erb", __dir__)
    )
    assert_includes listing, "parent_recordable.respond_to?(:title) && parent_recordable.title.present?"
    refute_includes listing, "is_a?(RecordingStudioAttachable::Placement)"
  end

  def test_collection_views_keep_main_structure_and_translate_at_value_sites
    editor = File.read(
      File.expand_path(
        "../app/views/recording_studio_attachable/attachment_collections/_editor.html.erb",
        __dir__
      )
    )
    grid = File.read(
      File.expand_path(
        "../app/views/recording_studio_attachable/attachment_collections/_grid.html.erb",
        __dir__
      )
    )
    facts = File.read(
      File.expand_path(
        "../app/views/recording_studio_attachable/attachment_collections/_file_facts.html.erb",
        __dir__
      )
    )

    assert_includes editor, "<%= collection.empty_message %>"
    refute_includes editor, "empty_message_overridden?"
    assert_includes editor, "Copy.remove_label(placement: collection.placement?)"
    assert_includes grid, "Copy.remove_label(placement: collection.placement?)"
    assert_includes grid, "Copy.image_name_fallback"
    assert_includes facts, "facts.labels.any?"
    assert_includes facts, "facts.labels.each"
    refute_includes facts, "display_labels"
    refute_includes facts, "content_type_key"
  end
end
