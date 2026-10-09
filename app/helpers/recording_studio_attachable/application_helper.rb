# frozen_string_literal: true

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

    def library_path_for(parent_or_library, **options)
      attachable_routes.library_path(parent_or_library, **options)
    end

    def libraries_path_for(parent_recording, **options)
      attachable_routes.recording_libraries_path(parent_recording, **options)
    end

    def library_picker_path_for(parent_or_library, **options)
      library = if RecordingStudioAttachable::Placements.library_recording?(parent_or_library)
                  parent_or_library
                else
                  RecordingStudioAttachable.library_for(parent_or_library)
                end
      attachable_routes.recording_attachment_picker_path(library, **options)
    end

    def library_title_for(library_recording)
      RecordingStudioAttachable::Placements.library_title(library_recording)
    end

    def library_description_for(library_recording)
      library_recording.try(:recordable).try(:description).to_s.strip.presence
    end

    def default_library?(library_recording)
      recordable = library_recording.try(:recordable)
      recordable.respond_to?(:default) && recordable.default
    end

    def library_photo_count(library_recording)
      if library_recording.respond_to?(:images)
        collection = library_recording.images(per_page: 1)
        return collection.total_count if collection.respond_to?(:total_count)

        Array(collection).size
      else
        Array(library_recording.try(:child_recordings)).count do |child|
          RecordingStudioAttachable::Placements.attachment_recording?(child)
        end
      end
    end

    def library_picker_switcher_payload(libraries)
      Array(libraries).each_with_object({}) do |library, payload|
        payload[library.id.to_s] = {
          pickerUrl: attachable_routes.recording_attachment_picker_path(library),
          uploadUrl: attachable_routes.recording_attachments_path(library)
        }
      end
    end

    def move_placement_ids(resolved, index, delta)
      ids = resolved.map { |item| item.placement_recording.id }
      target = index + delta
      return ids if target.negative? || target >= ids.length

      ids[index], ids[target] = ids[target], ids[index]
      ids
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
