# frozen_string_literal: true

require "pathname"

module RecordingStudioAttachable
  module GoogleDrive
    class Engine < ::Rails::Engine
      isolate_namespace RecordingStudioAttachable::GoogleDrive
      engine_name "recording_studio_attachable_google_drive"

      config.root = Pathname.new(File.expand_path(__dir__))

      initializer "recording_studio_attachable.google_drive.register_upload_provider" do |app|
        app.config.after_initialize do
          configuration = RecordingStudioAttachable.configuration.google_drive
          next unless configuration.enabled? && configuration.picker_configured?

          RecordingStudioAttachable.configure do |config|
            config.register_upload_provider(
              :google_drive,
              label: "Google Drive",
              icon: "cloud",
              url: ->(route_helpers:, recording:) { route_helpers.google_drive.recording_bootstrap_path(recording, format: :json) },
              strategy: :client_picker,
              launcher: "google_drive",
              bootstrap_url: lambda { |route_helpers:, recording:|
                route_helpers.google_drive.recording_bootstrap_path(recording, format: :json)
              },
              import_url: ->(route_helpers:, recording:) { route_helpers.google_drive.recording_imports_path(recording, format: :json) }
            )
          end
        end
      end
    end
  end
end
