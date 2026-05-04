# frozen_string_literal: true

require "recording_studio_attachable/version"
require "recording_studio_attachable/configuration"
require "recording_studio_attachable/authorization"
require "recording_studio_attachable/services/base_service"
require "recording_studio_attachable/engine"
require "recording_studio/capabilities/attachable"

module RecordingStudioAttachable
  class Error < StandardError; end
  class DependencyUnavailableError < Error; end

  class << self
    def configuration
      @configuration ||= Configuration.new
    end

    def configure
      yield(configuration) if block_given?
    end
  end
end
