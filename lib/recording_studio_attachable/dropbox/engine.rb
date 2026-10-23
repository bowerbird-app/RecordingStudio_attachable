# frozen_string_literal: true

require "pathname"
require_relative "integration"
require_relative "configuration"
require_relative "services/import_selected_files"

module RecordingStudioAttachable
  module Dropbox
    class Engine < ::Rails::Engine
      isolate_namespace RecordingStudioAttachable::Dropbox
      engine_name "recording_studio_attachable_dropbox"

      config.root = Pathname.new(File.expand_path(__dir__))

      initializer "recording_studio_attachable.dropbox.register_upload_provider" do |app|
        app.config.after_initialize { Engine.send(:register_upload_provider) }
      end

      class << self
        private

        def register_upload_provider
          return unless RecordingStudioAttachable.configuration.dropbox.available?

          RecordingStudioAttachable.configure do |config|
            config.register_upload_provider(:dropbox, **client_picker_options)
          end
        end

        def client_picker_options
          RecordingStudioAttachable::Adapter::ClientPicker.provider_options(
            label: "Dropbox",
            launcher: "dropbox",
            launcher_module: "controllers/recording_studio_attachable/dropbox_picker_launcher",
            allowed_payload_keys: %w[id],
            bootstrap_path: method(:bootstrap_path),
            import_path: method(:import_path),
            remote_importer: method(:remote_importer)
          )
        end

        def bootstrap_path(route_helpers:, recording:)
          route_helpers.dropbox.recording_bootstrap_path(recording, format: :json)
        end

        def import_path(route_helpers:, recording:)
          route_helpers.dropbox.recording_imports_path(recording, format: :json)
        end

        def remote_importer(parent_recording:, attachments:, actor: nil, impersonator: nil, **)
          Services::ImportSelectedFiles.call(
            parent_recording: parent_recording,
            file_ids: Adapter::Selection.from_attachments(attachments),
            actor: actor,
            impersonator: impersonator
          )
        end
      end
    end
  end
end

RecordingStudioAttachable.register_adapter_routes do
  next unless RecordingStudioAttachable::Dropbox::Integration.gem_loaded?

  mount RecordingStudioAttachable::Dropbox::Engine, at: "/dropbox", as: :dropbox
end
