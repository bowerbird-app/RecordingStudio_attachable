# frozen_string_literal: true

require "i18n"

module RecordingStudioAttachable
  # Rails I18n lookups for Attachable user-facing copy. Every call passes
  # `default:` English so a host locale without a fallback never shows
  # "translation missing". Prefer nested `recording_studio.attachable.*` keys;
  # when a legacy `recording_studio_attachable.*` key still exists, look it up
  # first with the nested key as the next default.
  module Copy
    PREFIX = "recording_studio.attachable"
    LEGACY_PREFIX = "recording_studio_attachable"

    module_function

    def t(key, **options)
      I18n.t("#{PREFIX}.#{key}", **options)
    end

    # Legacy-first lookup for keys that still ship under
    # `recording_studio_attachable.*` (wave-1 / pre-wave-2 callers).
    def legacy_t(legacy_key, nested_key, default:)
      I18n.t(
        "#{LEGACY_PREFIX}.#{legacy_key}",
        default: [:"#{PREFIX}.#{nested_key}", default]
      )
    end

    def field_label(field)
      t("collection.fields.#{field.key}", default: field.label)
    end

    def empty_message_for(association, english:)
      t("collection.empty_messages.#{association}", default: english)
    end

    # Map the editor's English Trash label to a locale key at render.
    # Any other label is already the caller's copy and passes through.
    def translate_remove_label(english)
      return t("collection.trash", default: "Trash") if english == "Trash"

      english
    end

    def type_label(mime_type, english:)
      t("file_facts.types.#{mime_type}", default: english)
    end

    def image_name_fallback
      t("collection.image_name_fallback", default: "image")
    end
  end
end
