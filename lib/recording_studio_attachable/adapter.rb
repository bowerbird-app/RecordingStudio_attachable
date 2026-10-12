# frozen_string_literal: true

module RecordingStudioAttachable
  class << self
    def register_adapter_configuration(key, configuration_class)
      Adapter.registry[key.to_sym] = configuration_class
      return unless instance_variable_defined?(:@configuration) && @configuration

      @configuration.install_adapter_configuration(key, configuration_class.new)
    end

    def adapter_route_blocks
      @adapter_route_blocks ||= []
    end

    def register_adapter_routes(&block)
      adapter_route_blocks << block
    end
  end

  module Adapter
    def self.registry
      @registry ||= {}
    end
  end
end
