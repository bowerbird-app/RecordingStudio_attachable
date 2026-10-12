# frozen_string_literal: true

require_relative "attachment_file_buttons_helper"
require_relative "attachment_collections_helper"

module RecordingStudioAttachable
  module ApplicationHelper
    include AttachmentFileButtonsHelper
    include AttachmentCollectionsHelper

    def authorized_attachment_preview_path(recording, variant_name)
      attachment = recording&.recordable
      return if attachment.blank?
      return unless attachment.respond_to?(:preview_target_named)
      return if attachment.preview_target_named(variant_name).blank?

      rails_url = attachable_routes.attachment_preview_file_path(recording, variant_name: variant_name)
      return rails_url unless attachment.respond_to?(:url_for_variant)

      attachment.url_for_variant(variant_name, rails_url: rails_url)
    end

    def authorized_attachment_file_path(recording)
      rails_url = attachable_routes.attachment_file_path(recording)
      attachment = recording.respond_to?(:recordable) ? recording.recordable : nil
      return rails_url unless attachment.respond_to?(:original_url)

      attachment.original_url(rails_url: rails_url)
    end

    def attachable_attachment_path(attachment_recording, **options)
      attachable_routes.attachment_path(attachment_recording, **options)
    end

    def attachable_attachment_imports_path(recording, **options)
      attachable_routes.recording_attachment_imports_path(recording, **options)
    end

    def library_path_for(parent_or_library, key: :default, **options)
      if RecordingStudioAttachable::Placements.library_recording?(parent_or_library)
        attachable_routes.library_path(parent_or_library, **options)
      else
        attachable_routes.recording_library_path(parent_or_library, key: key, **options)
      end
    end

    def library_picker_path_for(parent_or_library, key: :default, **options)
      library = if RecordingStudioAttachable::Placements.library_recording?(parent_or_library)
                  parent_or_library
                else
                  RecordingStudioAttachable.library_for(parent_or_library, key: key)
                end
      attachable_routes.recording_attachment_picker_path(library, **options)
    end

    def library_title_for(library_recording)
      RecordingStudioAttachable::Placements.library_title(library_recording)
    end

    def library_picker_switcher_payload(libraries)
      Array(libraries).each_with_object({}) do |library, payload|
        payload[library.id.to_s] = {
          pickerUrl: attachable_routes.recording_attachment_picker_path(library),
          uploadUrl: attachable_routes.recording_attachments_path(library)
        }
      end
    end

    def attachable_js_i18n(english_by_key)
      english_by_key.each_with_object({}) do |(key, english), payload|
        payload[key] = RecordingStudioAttachable::Copy.t(key, default: english)
      end
    end

    def attachable_upload_js_i18n
      attachable_js_i18n(
        "js.provider_unavailable" => "This upload provider is not available on this page.",
        "js.could_not_open_picker" => "Could not open the provider picker.",
        "js.finalization_failed" => "Finalization failed",
        "js.remote_file" => "Remote file",
        "js.file_exceeds_max_size" => "File exceeds the maximum allowed size",
        "js.type_not_allowed" => "%{type} is not allowed. Allowed types: %{types}",
        "js.unknown_type" => "Unknown type",
        "js.could_not_prepare_file" => "Could not prepare file for upload",
        "js.max_files_up_to" => "You can upload up to %{count} %{noun} at a time",
        "js.file_noun.one" => "file",
        "js.file_noun.other" => "files",
        "js.importing_from" => "Importing from %{provider}",
        "js.authentication_failed" => "Authentication failed.",
        "js.could_not_load_bootstrap" => "Could not load provider bootstrap data.",
        "js.optimizing_before_upload" => "Optimizing image before upload…",
        "js.uploading_name" => "Uploading %{name}",
        "js.remove_from_queue" => "Remove from upload queue",
        "js.remove_name_from_queue" => "Remove %{name} from upload queue",
        "js.retry" => "Retry",
        "js.progress" => "Progress",
        "js.cloud_import" => "Cloud import",
        "js.file_badge" => "FILE",
        "js.cloud" => "Cloud",
        "js.import_queued" => "Import queued",
        "js.importing" => "Importing",
        "js.creating_attachment" => "Creating attachment",
        "js.import_complete" => "Import complete",
        "js.import_failed" => "Import failed",
        "js.ready_to_import" => "Ready to import"
      )
    end

    def attachable_picker_js_i18n
      attachable_js_i18n(
        "picker.select_one_or_more" => "Select one or more",
        "picker.selected.one" => "%{count} selected",
        "picker.selected.other" => "%{count} selected",
        "picker.untitled_image" => "Untitled image",
        "picker.unable_to_load_library" => "Unable to load image library",
        "picker.unable_to_add_image" => "Unable to add image",
        "picker.uploading" => "Uploading",
        "picker.uploading_of" => "Uploading %{index} of %{total}",
        "picker.upload_completed_without_attachment" => "Upload completed without an attachment payload",
        "js.could_not_load_bootstrap" => "Could not load provider bootstrap data.",
        "js.progress" => "Progress",
        "js.uploading_name" => "Uploading %{name}"
      )
    end

    def attachable_collection_js_i18n
      attachable_js_i18n(
        "collection.saved" => "Saved",
        "flashes.could_not_save" => "Could not save."
      )
    end

    private

    def attachable_routes
      if respond_to?(:recording_studio_attachable, true)
        recording_studio_attachable
      else
        RecordingStudioAttachable::Engine.routes.url_helpers
      end
    end
  end
end
