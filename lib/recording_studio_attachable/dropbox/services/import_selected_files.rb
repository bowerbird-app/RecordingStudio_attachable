# frozen_string_literal: true

module RecordingStudioAttachable
  module Dropbox
    module Services
      class ImportSelectedFiles < RecordingStudioAttachable::Adapter::ImportSelectedFiles
        private

        def provider_key
          "dropbox"
        end

        def blank_selection_message
          "Select at least one Dropbox file to import"
        end

        def default_description
          "Imported from Dropbox"
        end

        def build_client
          RecordingStudioAttachable::Dropbox::Client.new(access_token: access_token)
        end
      end
    end
  end
end
