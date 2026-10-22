# frozen_string_literal: true

module GoogleDriveFakes
  DriveFile = Struct.new(:id, :name, :mime_type, :web_view_link, :folder, keyword_init: true) do
    def folder?
      !!folder
    end
  end

  DownloadedFile = Struct.new(:body, :filename, :content_type, keyword_init: true)
  Page = Struct.new(:entries, :next_cursor, keyword_init: true)
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
