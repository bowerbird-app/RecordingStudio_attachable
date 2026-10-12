# frozen_string_literal: true

require "test_helper"
require "i18n"
require "active_model"

class AttachmentValidationI18nTest < Minitest::Test
  class FakeAttachment
    include ActiveModel::Validations

    attr_accessor :content_type, :attachment_kind, :validation_options

    validate :content_type_must_be_allowed
    validate :attachment_kind_must_be_enabled

    def initialize(content_type:, attachment_kind:, validation_options: {})
      @content_type = content_type
      @attachment_kind = attachment_kind
      @validation_options = validation_options
    end

    private

    def content_type_must_be_allowed
      return if content_type.blank?
      return if RecordingStudioAttachable.configuration.allowed_content_type?(
        content_type,
        allowed_content_types: validation_options[:allowed_content_types]
      )

      errors.add(
        :content_type,
        RecordingStudioAttachable::Copy.t(
          "errors.content_type_not_allowed",
          default: "is not allowed"
        )
      )
    end

    def attachment_kind_must_be_enabled
      return if attachment_kind.blank?
      return if RecordingStudioAttachable.configuration.attachment_kind_enabled?(
        attachment_kind,
        enabled_attachment_kinds: validation_options[:enabled_attachment_kinds]
      )

      errors.add(
        :attachment_kind,
        RecordingStudioAttachable::Copy.t(
          "errors.attachment_kind_not_enabled",
          default: "is not enabled"
        )
      )
    end
  end

  def setup
    @previous_backend = I18n.backend
    @previous_load_path = I18n.load_path.dup
    I18n.backend = I18n::Backend::Simple.new
    I18n.load_path = [File.expand_path("../config/locales/en.yml", __dir__)]
    I18n.backend.load_translations
    I18n.locale = :en
  end

  def teardown
    I18n.load_path = @previous_load_path
    I18n.backend = @previous_backend
  end

  def test_english_error_details_match_main_string_types
    attachment = FakeAttachment.new(
      content_type: "application/zip",
      attachment_kind: "archive",
      validation_options: {
        allowed_content_types: ["image/*"],
        enabled_attachment_kinds: %i[image]
      }
    )

    refute attachment.valid?

    assert_equal [{ error: "is not allowed" }], attachment.errors.details[:content_type]
    assert_equal [{ error: "is not enabled" }], attachment.errors.details[:attachment_kind]
    assert_includes attachment.errors.full_messages, "Content type is not allowed"
    assert_includes attachment.errors.full_messages, "Attachment kind is not enabled"
  end

  def test_french_full_messages_use_translated_string_types
    I18n.available_locales = Array(I18n.available_locales) | %i[en fr]
    I18n.backend.store_translations(
      :fr,
      {
        recording_studio: {
          attachable: {
            errors: {
              content_type_not_allowed: "n'est pas autorisé",
              attachment_kind_not_enabled: "n'est pas activé"
            }
          }
        },
        activemodel: {
          attributes: {
            "attachment_validation_i18n_test/fake_attachment": {
              content_type: "Type de contenu",
              attachment_kind: "Genre de pièce jointe"
            }
          }
        }
      }
    )

    attachment = FakeAttachment.new(
      content_type: "application/zip",
      attachment_kind: "archive",
      validation_options: {
        allowed_content_types: ["image/*"],
        enabled_attachment_kinds: %i[image]
      }
    )

    I18n.with_locale(:fr) do
      refute attachment.valid?
      assert_equal [{ error: "n'est pas autorisé" }], attachment.errors.details[:content_type]
      assert_includes attachment.errors.full_messages.join(" "), "n'est pas autorisé"
      assert_includes attachment.errors.full_messages.join(" "), "n'est pas activé"
    end
  end

  def test_host_override_wins_for_validation_string_types
    host = File.expand_path("dummy/test/locales/attachable_host_override.en.yml", __dir__)
    I18n.load_path = @previous_load_path + [
      File.expand_path("../config/locales/en.yml", __dir__),
      host
    ]
    I18n.backend = I18n::Backend::Simple.new
    I18n.backend.load_translations

    attachment = FakeAttachment.new(
      content_type: "application/zip",
      attachment_kind: "archive",
      validation_options: {
        allowed_content_types: ["image/*"],
        enabled_attachment_kinds: %i[image]
      }
    )

    refute attachment.valid?
    assert_equal [{ error: "HOST is not allowed" }], attachment.errors.details[:content_type]
    assert_equal [{ error: "HOST is not enabled" }], attachment.errors.details[:attachment_kind]
  ensure
    I18n.load_path = @previous_load_path
    I18n.backend = @previous_backend
  end
end
