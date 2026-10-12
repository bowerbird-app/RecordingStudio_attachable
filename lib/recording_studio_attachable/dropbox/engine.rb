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
          return unless upload_provider_enabled?

          RecordingStudioAttachable.configure do |config|
            config.register_upload_provider(:dropbox, **upload_provider_options)
          end
        end

        def upload_provider_enabled?
          RecordingStudioAttachable.configuration.dropbox.available?
        end

        def upload_provider_options # rubocop:disable Metrics/MethodLength
          {
            label: "Dropbox",
            icon: "cloud",
            url: ->(route_helpers:, recording:) { bootstrap_path(route_helpers:, recording:) },
            strategy: :client_picker,
            launcher: "dropbox",
            launcher_module: "controllers/recording_studio_attachable/dropbox_picker_launcher",
            bootstrap_url: ->(route_helpers:, recording:) { bootstrap_path(route_helpers:, recording:) },
            import_url: ->(route_helpers:, recording:) { import_path(route_helpers:, recording:) },
            remote_importer: method(:remote_importer),
            allowed_payload_keys: %w[id]
          }
        end

        def bootstrap_path(route_helpers:, recording:)
          route_helpers.dropbox.recording_bootstrap_path(recording, format: :json)
        end

        def import_path(route_helpers:, recording:)
          route_helpers.recording_attachment_imports_path(recording, format: :json)
        end

        def remote_importer(parent_recording:, attachments:, actor: nil, impersonator: nil, context: nil)
          access_token = RecordingStudioAttachable::Dropbox::SessionAccessToken.fetch(session: context.session)
          selections = normalized_selections(attachments)

          RecordingStudioAttachable::Dropbox::Services::ImportSelectedFiles.call(
            parent_recording: parent_recording,
            file_ids: selections,
            access_token: access_token,
            actor: actor,
            impersonator: impersonator
          )
        end

        def normalized_selections(attachments)
          Array(attachments).map do |payload|
            provider_payload = payload.fetch(:provider_payload, {}).to_h.stringify_keys
            provider_payload.merge(
              "name" => payload[:name],
              "description" => payload[:description],
              "metadata" => payload.fetch(:metadata, {}).to_h.except("provider", :provider)
            ).compact_blank
          end
        end
      end
    end
  end
end

RecordingStudioAttachable.register_adapter_routes do
  mount RecordingStudioAttachable::Dropbox::Engine, at: "/dropbox", as: :dropbox
end
