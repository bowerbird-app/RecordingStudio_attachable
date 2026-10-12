# frozen_string_literal: true

require "test_helper"
require "i18n"

class AttachmentCollectionI18nTest < Minitest::Test
  def setup
    @previous_backend = I18n.backend
    @previous_load_path = I18n.load_path.dup
    @previous_available = I18n.available_locales
    I18n.available_locales = Array(I18n.available_locales) | %i[en fr]
    I18n.backend = I18n::Backend::Simple.new
    I18n.load_path = [File.expand_path("../config/locales/en.yml", __dir__)]
    I18n.backend.load_translations
    I18n.locale = :en
  end

  def teardown
    I18n.load_path = @previous_load_path
    I18n.backend = @previous_backend
    I18n.available_locales = @previous_available
  end

  def test_empty_messages_constants_stay_english_public_api
    assert_equal "No images yet.", RecordingStudioAttachable::AttachmentCollection::EMPTY_MESSAGES.fetch(:images)
    assert_equal "Nothing here yet.", RecordingStudioAttachable::AttachmentCollection::EMPTY_MESSAGES.fetch(:attachments)
  end

  def test_empty_message_translates_at_call_time_with_english_default
    collection = RecordingStudioAttachable::AttachmentCollection.allocate
    collection.instance_variable_set(:@association, :images)
    collection.instance_variable_set(:@empty_message, nil)

    assert_equal "No images yet.", collection.empty_message

    I18n.backend.store_translations(
      :fr,
      { recording_studio: { attachable: { collection: { empty_messages: { images: "Pas encore d'images." } } } } }
    )
    I18n.with_locale(:fr) do
      assert_equal "Pas encore d'images.", collection.empty_message
    end
  end

  def test_remove_label_translates_at_call_time
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
      assert_equal "Corbeille", collection.remove_label
      collection.instance_variable_set(:@association, :placements)
      assert_equal "Retirer d'ici", collection.remove_label
    end
  end

  def test_display_labels_constant_left_as_is
    assert_equal(
      { list: "List", carousel: "Slides", grid: "Grid" },
      RecordingStudioAttachable::AttachmentCollectionDisplay::LABELS
    )
    assert_equal "Slides", RecordingStudioAttachable::AttachmentCollectionDisplay.label(:carousel)
  end

  def test_type_labels_constant_stays_english_and_call_time_translates
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
      assert_equal "JPEG-FR", facts.type_label
    end
  end
end
