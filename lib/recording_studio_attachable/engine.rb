# frozen_string_literal: true

module RecordingStudioAttachable
  class Engine < ::Rails::Engine
    isolate_namespace RecordingStudioAttachable

    initializer "recording_studio_attachable.assets" do |app|
      next unless app.config.respond_to?(:assets)

      app.config.assets.paths << root.join("app/javascript")
    end

    initializer "recording_studio_attachable.adapter_routes", after: :load_config_initializers do
      RecordingStudioAttachable::Engine.routes.append do
        RecordingStudioAttachable.adapter_route_blocks.each_value do |route_block|
          instance_eval(&route_block)
        end
      end
    end

    initializer "recording_studio_attachable.load_config" do |app|
      RecordingStudioAttachable::Engine.send(:load_yaml_config, app)
      RecordingStudioAttachable::Engine.send(:load_x_config, app)
    end

    initializer "recording_studio_attachable.register_recording_studio_integration" do |app|
      RecordingStudioAttachable::Engine.register_recording_studio_integration

      app.config.after_initialize do
        RecordingStudioAttachable::Engine.register_recording_studio_integration
      end
    end

    initializer "recording_studio_attachable.filter_parameters" do |app|
      app.config.filter_parameters += %i[signed_blob_id checksum]
    end

    initializer "recording_studio_attachable.api" do
      config.to_prepare do
        if defined?(::RecordingStudioApi::ApiController) && !(RecordingStudioApi::ApiController < ActiveStorage::SetCurrent)
          RecordingStudioApi::ApiController.include ActiveStorage::SetCurrent
        end

        RecordingStudioAttachable::Api.register!
      end
    end

    initializer "recording_studio_attachable.storage_limit" do |app|
      app.config.to_prepare do
        RecordingStudioAttachable::StorageLimit.register_usage!
        RecordingStudioAttachable::StorageLimit.install_release_hook!
      end
    end

    initializer "recording_studio_attachable.action_view_helpers" do
      ActiveSupport.on_load(:action_view) do
        include RecordingStudioAttachable::ApplicationHelper
      end
    end

    def self.register_recording_studio_integration
      return unless defined?(RecordingStudio)

      register_attachable_capabilities
      register_attachment_recordable_type
    end

    def self.register_attachable_capabilities
      register_one_capability(:attachable, RecordingStudio::Capabilities::Attachable, "RecordingStudioAttachable::Attachment")
    end

    def self.register_one_capability(name, capability, child)
      RecordingStudio.register_capability(
        name,
        recording_methods: capability::RecordingMethods,
        source: "recording_studio_attachable",
        child_recordables: [child]
      )
    end

    def self.register_attachment_recordable_type
      return unless attachable_parent_types_registered?

      register_recordable_type_if_needed("RecordingStudioAttachable::Attachment")
    end

    def self.register_recordable_type_if_needed(type_name)
      return if Array(RecordingStudio.configuration.recordable_types).map(&:to_s).include?(type_name)
      return if defined?(RecordingStudio::Recording) && !RecordingStudio::Recording.respond_to?(:delegated_type)

      RecordingStudio.register_recordable_type(type_name)
    end

    def self.attachable_parent_types_registered?
      capability_parent_types_registered?(:attachable)
    end

    def self.capability_parent_types_registered?(capability_name)
      configuration = RecordingStudio.configuration
      return false unless configuration.respond_to?(:enabled_recordable_types_for)

      Array(configuration.enabled_recordable_types_for(capability_name)).any?
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

  Engine.initializer "recording_studio_attachable.metrics" do
    Engine.config.to_prepare do
      require "recording_studio_attachable/metrics"
      Metrics.register!
    end
  end
end
