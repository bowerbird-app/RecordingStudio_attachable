# frozen_string_literal: true

module RecordingStudioAttachable
  class Engine < ::Rails::Engine
    isolate_namespace RecordingStudioAttachable

    initializer "recording_studio_attachable.load_config" do |app|
      if app.respond_to?(:config_for)
        begin
          yaml = app.config_for(:recording_studio_attachable)
          RecordingStudioAttachable.configuration.merge!(yaml) if yaml.respond_to?(:each)
        rescue StandardError
          nil
        end
      end

      if app.config.respond_to?(:x) && app.config.x.respond_to?(:recording_studio_attachable)
        xcfg = app.config.x.recording_studio_attachable
        config_hash = xcfg.respond_to?(:to_h) ? xcfg.to_h : {}
        RecordingStudioAttachable.configuration.merge!(config_hash)
      end
    end

    initializer "recording_studio_attachable.register_recording_studio_integration" do
      next unless defined?(RecordingStudio)

      RecordingStudio.register_recordable_type("RecordingStudioAttachable::Attachment")
      RecordingStudio.register_capability(
        :attachable,
        RecordingStudio::Capabilities::Attachable::RecordingMethods
      )
    end
  end
end
