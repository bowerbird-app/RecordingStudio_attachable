# frozen_string_literal: true

module RecordingStudioAttachable
  module Adapters
    class Attachment < RecordingStudioLibrary::Adapters::Base
      def type_label
        return I18n.t("recording_studio.attachable.library.image_type") if recordable.blank?

        image? ? I18n.t("recording_studio.attachable.library.image_type") : I18n.t("recording_studio.attachable.library.file_type")
      end

      def icon
        image? ? :photo : :document
      end

      def title
        recordable_value(:name) || super
      end

      def search_text
        [
          title,
          recordable_value(:caption),
          recordable_value(:credit),
          recordable_value(:alt_text),
          recordable_value(:description),
          recordable_value(:original_filename),
          type_label
        ].compact.join(" ")
      end

      def thumbnail(view)
        image_preview(view, variant: :square_med, size_class: "h-full w-full min-h-24", rounded: false)
      end

      def preview(view)
        image_preview(view, variant: :square_small, size_class: "h-12 w-12", rounded: true)
      end

      def full_view(view)
        image_preview(view, variant: :large, size_class: "h-80 w-full", rounded: true)
      end

      def edit_fields(view, form)
        view.safe_join(
          [
            text_field(view, form, :name, title, "recording_studio.attachable.attachments.name"),
            text_field(view, form, :caption, recordable_value(:caption), "recording_studio.attachable.attachments.caption"),
            text_field(view, form, :credit, recordable_value(:credit), "recording_studio.attachable.attachments.credit"),
            text_field(view, form, :alt_text, recordable_value(:alt_text), "recording_studio.attachable.attachments.alt_text")
          ]
        )
      end

      private

      def image?
        recordable.respond_to?(:image?) ? recordable.image? : attachment_kind == "image"
      end

      def attachment_kind
        recordable_value(:attachment_kind).to_s
      end

      def image_preview(view, variant:, size_class:, rounded:)
        path = preview_path(view, variant)
        rounding = rounded ? "rounded-lg" : nil
        classes = ["overflow-hidden", size_class, rounding, "bg-(--surface-muted-background-color)"].compact.join(" ")
        return file_swatch(view, classes) if path.blank?

        view.tag.div(class: classes) do
          view.image_tag(path, alt: title, class: "h-full w-full object-cover")
        end
      end

      def file_swatch(view, classes)
        view.tag.div(class: "#{classes} flex items-center justify-center") do
          view.tag.span(title.to_s.first.to_s.upcase.presence || "F", class: "text-lg font-semibold")
        end
      end

      def preview_path(view, variant)
        return unless image?
        return unless view.respond_to?(:authorized_attachment_preview_path)

        view.authorized_attachment_preview_path(recording, variant)
      rescue StandardError
        nil
      end

      def text_field(view, form, attribute, value, label_key)
        view.render(
          FlatPack::TextInput::Component.new(
            name: field_name(form, attribute),
            label: I18n.t(label_key),
            value: value
          )
        )
      end

      def field_name(form, attribute)
        object_name = form.respond_to?(:object_name) ? form.object_name : nil
        return attribute if object_name.blank?

        "#{object_name}[#{attribute}]"
      end
    end
  end
end
