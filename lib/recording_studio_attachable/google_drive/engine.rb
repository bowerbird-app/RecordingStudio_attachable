# frozen_string_literal: true

require "pathname"
require_relative "configuration"
require_relative "oauth_client"
require_relative "client"
require_relative "session_access_token"
require_relative "services/import_selected_files"

module RecordingStudioAttachable
  module GoogleDrive
    class Engine < ::Rails::Engine
      isolate_namespace RecordingStudioAttachable::GoogleDrive
      engine_name "recording_studio_attachable_google_drive"

      config.root = Pathname.new(File.expand_path(__dir__))

      initializer "recording_studio_attachable.google_drive.register_upload_provider" do |app|
        app.config.after_initialize { Engine.send(:register_upload_provider) }
      end

      class << self
        private

        def register_upload_provider
          return unless RecordingStudioAttachable.configuration.google_drive.available?

          RecordingStudioAttachable.configure do |config|
            config.register_upload_provider(:google_drive, **client_picker_options)
          end
        end

        def client_picker_options
          RecordingStudioAttachable::Adapter::ClientPicker.provider_options(
            label: "Google Drive",
            launcher: "google_drive",
            launcher_module: "controllers/recording_studio_attachable/google_drive_picker_launcher",
            allowed_payload_keys: %w[id resource_key],
            bootstrap_path: method(:bootstrap_path),
            import_path: method(:import_path),
            remote_importer: method(:remote_importer)
          )
        end

        def bootstrap_path(route_helpers:, recording:)
          route_helpers.google_drive.recording_bootstrap_path(recording, format: :json)
        end

        def import_path(route_helpers:, recording:)
          route_helpers.google_drive.recording_imports_path(recording, format: :json)
        end

        def remote_importer(parent_recording:, attachments:, actor: nil, impersonator: nil, context: nil)
          RecordingStudioAttachable::Adapter::ClientPicker.import_from_session(
            context: context,
            attachments: attachments,
            session_token_class: SessionAccessToken,
            import_class: Services::ImportSelectedFiles,
            parent_recording: parent_recording,
            actor: actor,
            impersonator: impersonator
          )
        end
      end
    end
  end
end

RecordingStudioAttachable.register_adapter_routes do
  mount RecordingStudioAttachable::GoogleDrive::Engine, at: "/google_drive", as: :google_drive
end
