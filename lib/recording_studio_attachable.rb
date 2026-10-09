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
    end

    def library_for(parent_recording, key: :default, actor: nil)
      result = Services::FindOrCreateLibrary.call(
        parent_recording: parent_recording,
        key: key,
        actor: actor
      )
      raise ArgumentError, result.error.presence || "Could not change the library" if result.failure?

      result.value
    end

    def libraries_for(parent_recording)
      Services::LibraryQuery.live_for_parent(parent_recording)
    end

    def libraries_in_root(recording)
      Services::LibraryQuery.live_in_root(recording)
    end
  end
end

require "active_support/core_ext/numeric/bytes"
require "recording_studio"

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
require "recording_studio_attachable/metrics"
require "recording_studio/capabilities/attachable"
