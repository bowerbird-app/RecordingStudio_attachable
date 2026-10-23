# frozen_string_literal: true

module RecordingStudioAttachable
  class << self
    def register_adapter_configuration(key, configuration_class)
      Adapter.registry[key.to_sym] = configuration_class
      return unless instance_variable_defined?(:@configuration) && @configuration

      @configuration.install_adapter_configuration(key, configuration_class.new)
    end

    def adapter_route_blocks
      @adapter_route_blocks ||= {}
    end

    def register_adapter_routes(key, &block)
      raise ArgumentError, "adapter route key is required" if key.blank?
      raise ArgumentError, "adapter routes require a block" unless block

      adapter_key = key.to_sym
      if adapter_route_blocks.key?(adapter_key)
        raise ArgumentError, "adapter routes already registered for #{adapter_key.inspect}"
      end

      adapter_route_blocks[adapter_key] = block
    end
  end

  module Adapter
    def self.registry
      @registry ||= {}
    end
  end
end
