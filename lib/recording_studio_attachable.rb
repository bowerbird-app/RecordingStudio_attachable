# frozen_string_literal: true

module RecordingStudioAttachable
  class Error < StandardError; end
  class DependencyUnavailableError < Error; end

  class << self
    def configuration
      @configuration ||= Configuration.new
    end

    def register_upload_provider(key = nil, **options)
      configuration.register_upload_provider(key, **options)
    end

    def configure
      yield(configuration) if block_given?
    end
  end
end

require "active_support/core_ext/numeric/bytes"

require "recording_studio_attachable/version"
require "recording_studio_attachable/configuration"
require "recording_studio_attachable/upload_provider"
require "recording_studio_attachable/authorization"
require "recording_studio_attachable/services/base_service"
require "recording_studio_attachable/google_drive/oauth_client"
require "recording_studio_attachable/google_drive/client"
require "recording_studio_attachable/google_drive/session_access_token"
require "recording_studio_attachable/google_drive/services/import_selected_files"
require "recording_studio_attachable/google_drive/engine"
require "recording_studio_attachable/engine"
require "recording_studio/capabilities/attachable"
