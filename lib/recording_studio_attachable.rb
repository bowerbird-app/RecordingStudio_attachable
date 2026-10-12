# frozen_string_literal: true

module RecordingStudioAttachable
  class Error < StandardError; end
  class ConfigurationError < Error; end
  class DependencyUnavailableError < Error; end
  class StorageLimitUnknown < Error; end
  class StorageLimitError < Error; end

  class << self
    def configuration
      @configuration ||= Configuration.new
    end

    def storage_bytes_for(root_recording)
      StorageLimit.bytes_for(root_recording)
    end

    def register_upload_provider(key = nil, **options)
      configuration.register_upload_provider(key, **options)
    end

    def configure
      yield(configuration) if block_given?
      configuration.sync_library_configuration!
    end

    def library_for(parent_recording, key: :default, actor: nil)
      RecordingStudioLibrary.library_for(parent_recording, key: key, actor: actor)
    end

    def find_library(parent_recording, key: :default)
      RecordingStudioLibrary.find_library(parent_recording, key: key)
    end

    def libraries_for(parent_recording)
      RecordingStudioLibrary.libraries_for(parent_recording)
    end

    def libraries_in_root(recording)
      RecordingStudioLibrary.libraries_in_root(recording)
    end

    def place_library_image(holder, attachment_recording:, actor: nil)
      RecordingStudioLibrary.place!(holder, attachment_recording, actor: actor)
    end

    def upload_to_library_and_place(parent_recording:, library_recording: nil, actor: nil, **upload)
      Services::UploadToLibraryAndPlace.call(
        parent_recording: parent_recording,
        library_recording: library_recording,
        actor: actor,
        **upload
      ).then do |result|
        raise ArgumentError, result.error.presence || "Could not add that item" if result.failure?

        result.value
      end
    end

    def library_placements(holder, include_trashed_images: false, **options)
      Placements.resolve(holder, include_trashed_images: include_trashed_images, **options)
    end

    def reorder_library_placements!(holder, ordered_recording_ids: nil, actor: nil, **options)
      RecordingStudioLibrary.reorder!(
        holder,
        ordered_recording_ids,
        actor: actor,
        **options
      )
    end

    def remove_library_placement(holder, placement_recording:, actor: nil)
      RecordingStudioLibrary.remove!(placement_recording, holder: holder, actor: actor)
    end
  end
end

require "active_support/core_ext/numeric/bytes"
require "recording_studio"
require "recording_studio_library"

require "recording_studio_attachable/version"
require "recording_studio_attachable/configuration"
require "recording_studio_attachable/direct_url"
require "recording_studio_attachable/attachment_urls"
require "recording_studio_attachable/attachment_file_button"
require "recording_studio_attachable/attachment_file_facts"
require "recording_studio_attachable/attachment_collection"
require "recording_studio_attachable/attachment_file_button_responses"
require "recording_studio_attachable/upload_provider"
require "recording_studio_attachable/library_authorization"
require "recording_studio_attachable/authorization"
require "recording_studio_attachable/storage_release"
require "recording_studio_attachable/storage_limit"
require "recording_studio_attachable/library_attachment"
require "recording_studio_attachable/adapters/attachment"
require "recording_studio_attachable/placements"
require "recording_studio_attachable/services/base_service"
require "recording_studio/capabilities/image_library"
require "recording_studio/capabilities/library_placement"
require "recording_studio_attachable/google_drive/oauth_client"
require "recording_studio_attachable/google_drive/client"
require "recording_studio_attachable/google_drive/session_access_token"
require "recording_studio_attachable/google_drive/services/import_selected_files"
require "recording_studio_attachable/google_drive/engine"
require "recording_studio_attachable/engine"
require "recording_studio/capabilities/attachable"

RecordingStudioLibrary.register_adapter(
  "RecordingStudioAttachable::Attachment",
  RecordingStudioAttachable::Adapters::Attachment
)
