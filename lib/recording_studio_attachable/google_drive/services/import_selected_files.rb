# frozen_string_literal: true

module RecordingStudioAttachable
  module GoogleDrive
    module Services
      class ImportSelectedFiles < RecordingStudioAttachable::Adapter::ImportSelectedFiles
        private

        def provider_key
          "google_drive"
        end

        def blank_selection_message
          "Select at least one Google Drive file to import"
        end

        def default_description
          "Imported from Google Drive"
        end

        def extra_selection_keys
          { "resource_key" => %i[resource_key resourceKey] }
        end

        def build_client
          RecordingStudioAttachable::GoogleDrive::Client.new(access_token: access_token)
        end
      end
    end
  end
end
