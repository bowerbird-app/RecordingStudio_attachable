# frozen_string_literal: true

require "pathname"
require_relative "configuration"
require_relative "oauth_client"
require_relative "client"
require_relative "session_access_token"
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
          route_helpers.recording_studio_attachable.recording_attachment_imports_path(recording, format: :json)
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
  mount RecordingStudioAttachable::Dropbox::Engine, at: "/dropbox", as: :dropbox
end
