# frozen_string_literal: true

unless defined?(::RecordingStudioGoogleDrive)
  module RecordingStudioGoogleDrive
    class Error < StandardError; end
    class ReconnectRequired < Error; end
    class RequestError < Error; end
  end
end

module GoogleDriveFakes
  DriveFile = Struct.new(:id, :name, :mime_type, :web_view_link, :folder, :size, keyword_init: true) do
    def folder?
      !!folder
    end
  end

  DownloadedFile = Struct.new(:body, :filename, :content_type, keyword_init: true)

  class Page
    attr_reader :entries, :next_cursor

    def initialize(entries:, next_cursor: nil)
      @entries = entries
      @next_cursor = next_cursor
    end
  end
  Connection = Struct.new(:access_token, :expires_at, :needs_reconnect, keyword_init: true) do
    def needs_reconnect?
      !!needs_reconnect
    end
  end

  module_function

  def with_gem_loaded(&)
    RecordingStudioAttachable::GoogleDrive::Integration.stub(:gem_loaded?, true, &)
  end
end
