# frozen_string_literal: true

require "recording_studio_attachable/attachment_collection"
require "recording_studio_attachable/attachment_file_button"
require "recording_studio_attachable/attachment_file_facts"

module RecordingStudioAttachable
  module AttachmentCollectionsHelper
    def attachment_collection_editor(
      recording,
      association:,
      fields:,
      sortable: false,
      preview: :square,
      displays: [:list],
      default_display: nil,
      side_preview: false,
      items_per_view: 1,
      items: nil,
      empty_message: nil,
      url: nil,
      return_to: nil,
      upload_button: nil,
      remove_label: nil,
      remove_path: nil,
      orderable_message: nil
    )
      collection = AttachmentCollection.for(
        recording:, association:, fields:, sortable:, preview:, displays:, default_display:,
        side_preview:, items_per_view:, return_to:, items:, empty_message:,
        remove_label:, remove_path:, orderable_message:
      )
      editor = render partial: "recording_studio_attachable/attachment_collections/editor",
                      locals: editor_locals(collection, recording, url, return_to)
      with_attachment_collection_upload_button(editor, recording, upload_button, return_to:)
    end

    # upload_button: true, or { presentation: :page|:modal, label: "Add", target: "frame-id" }.
    # Collections hold many files, so the button always adds and never switches to Change.
    def with_attachment_collection_upload_button(editor, recording, upload_button, return_to:)
      button = attachment_collection_upload_button(recording, upload_button, return_to:)
      return editor if button.blank?

      tag.div(class: "flex w-full flex-col gap-4") do
        safe_join([tag.div(button, class: "flex flex-wrap items-center gap-3"), editor])
      end
    end

    def attachment_collection_upload_button(recording, options, return_to:)
      return if options.blank?

      options = options == true ? {} : options.to_h.symbolize_keys
      render partial: "recording_studio_attachable/attachment_file_buttons/button",
             locals: collection_upload_button_locals(recording, options, return_to)
    end

    def attachable_attachment_collection_path(recording, **options)
      attachable_routes.recording_attachment_collection_path(recording, **options)
    end

    def attachable_destroy_attachment_path(recording, **options)
      attachable_routes.destroy_attachment_path(recording, **options)
    end

    def attachment_collection_remove_path(collection, row, return_to:)
      params = AttachmentFileButton.redirect_params(return_to: return_to)
      custom = collection.remove_path
      return custom.call(row, params) if custom

      attachable_destroy_attachment_path(row.recording, **params)
    end

    def attachment_collection_image_path(_collection, row, return_to:)
      attachable_attachment_path(row.recording, **AttachmentFileButton.redirect_params(return_to: return_to))
    end

    def attachment_collection_save_path(_collection, recording, url)
      return url if url.present?

      attachable_attachment_collection_path(recording)
    end

    private

    def collection_upload_button_locals(recording, options, return_to)
      AttachmentFileButton.locals(
        recording:,
        return_to: return_to.presence || request&.fullpath,
        target: options[:target],
        add_label: options.fetch(:label, AttachmentFileButton::DEFAULT_ADD_LABEL),
        presentation: options[:presentation]
      ).merge(attachment_recording: nil)
    end

    def editor_locals(collection, recording, url, return_to)
      {
        collection: collection,
        url: attachment_collection_save_path(collection, recording, url),
        return_to: return_to
      }
    end
  end
end
