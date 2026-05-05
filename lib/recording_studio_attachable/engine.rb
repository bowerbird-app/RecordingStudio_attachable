# frozen_string_literal: true

module RecordingStudioAttachable
  class Engine < ::Rails::Engine
    isolate_namespace RecordingStudioAttachable

    initializer "recording_studio_attachable.assets" do |app|
      next unless app.config.respond_to?(:assets)

      app.config.assets.paths << root.join("app/javascript")
    end

    initializer "recording_studio_attachable.load_config" do |app|
      RecordingStudioAttachable::Engine.send(:load_yaml_config, app)
      RecordingStudioAttachable::Engine.send(:load_x_config, app)
    end

    initializer "recording_studio_attachable.register_recording_studio_integration" do
      next unless defined?(RecordingStudio)

      RecordingStudio.register_recordable_type("RecordingStudioAttachable::Attachment")
      RecordingStudio.register_capability(
        :attachable,
        RecordingStudio::Capabilities::Attachable::RecordingMethods
      )
    end

    class << self
      private

      def load_yaml_config(app)
        return unless app.respond_to?(:config_for)

        yaml = app.config_for(:recording_studio_attachable)
        RecordingStudioAttachable.configuration.merge!(yaml) if yaml.respond_to?(:each)
      rescue StandardError => e
        log_config_warning("recording_studio_attachable config_for load failed: #{e.class}: #{e.message}")
      end

      def load_x_config(app)
        return unless app.config.respond_to?(:x) && app.config.x.respond_to?(:recording_studio_attachable)

        xcfg = app.config.x.recording_studio_attachable
        config_hash = xcfg.respond_to?(:to_h) ? xcfg.to_h : {}
        RecordingStudioAttachable.configuration.merge!(config_hash)
      end

      def log_config_warning(message)
        if defined?(Rails) && Rails.respond_to?(:logger) && Rails.logger.present?
          Rails.logger.warn(message)
        else
          warn(message)
        end
      end
    end
  end
end
