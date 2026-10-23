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

        def remote_importer(parent_recording:, attachments:, actor: nil, impersonator: nil, **options)
          Services::ImportSelectedFiles.call(
            parent_recording: parent_recording,
            file_ids: Adapter::Selection.from_attachments(attachments),
            actor: actor,
            impersonator: impersonator
          )
        rescue StandardError => e
          map_remote_import_error(e, parent_recording: parent_recording, context: options[:context])
        end

        def map_remote_import_error(error, parent_recording:, context:)
          return reconnect_import_result(parent_recording, context) if Integration.reconnect_required?(error)
          raise unless Integration.request_error?(error)

          RecordingStudioAttachable::Services::BaseService::Result.new(success: false, error: error.message)
        end

        def reconnect_import_result(parent_recording, context)
          RecordingStudioAttachable::Services::BaseService::Result.new(
            success: false,
            error: Copy.t("dropbox.reconnect_to_continue", default: "Reconnect Dropbox to continue"),
            errors: remote_import_reconnect_payload(parent_recording, context)
          )
        end

        def remote_import_reconnect_payload(parent_recording, context)
          {
            authenticity_token: (context.form_authenticity_token if context.respond_to?(:form_authenticity_token)),
            oauth_connect_url: remote_import_oauth_connect_path,
            connect_url: remote_import_connect_url(parent_recording, context),
            return_to: remote_import_return_to(parent_recording, context)
          }.compact
        end

        def remote_import_oauth_connect_path
          return unless Integration.oauth_loaded?

          ::RecordingStudioOauth::Engine.routes.url_helpers.outbound_connect_path(
            provider: Integration.provider_key
          )
        end

        def remote_import_connect_url(parent_recording, context)
          dropbox = context.dropbox if context.respond_to?(:dropbox)
          return unless dropbox.respond_to?(:recording_connect_path)

          dropbox.recording_connect_path(parent_recording, popup: 1, provider_key: "dropbox")
        end

        def remote_import_return_to(parent_recording, context)
          dropbox = context.dropbox if context.respond_to?(:dropbox)
          return unless dropbox.respond_to?(:recording_connected_path)

          dropbox.recording_connected_path(parent_recording, popup: 1)
        end
      end
    end
  end
end

RecordingStudioAttachable.register_adapter_routes do
  next unless RecordingStudioAttachable::Dropbox::Integration.gem_loaded?

  mount RecordingStudioAttachable::Dropbox::Engine, at: "/dropbox", as: :dropbox
end
