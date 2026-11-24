# frozen_string_literal: true

module RecordingStudioAttachable
  module McpCopy
    module Names
      module_function

      def list(types, api:)
        Array(types).flat_map { |type| for_type(type, api: api) }
      end

      def for_type(type, api:)
        actions_for(type, api).map { |action| McpCopy.tool_name(type, action) }
      end

      def actions_for(type, api)
        return McpCopy::ACTIONS if api.nil?

        McpCopy::ACTIONS.select { |action| supported?(type, action, api) }
      end

      def supported?(type, action, api)
        registration = registration_for(type, api)
        registration.respond_to?(:supports_capability_action?) && registration.supports_capability_action?(action)
      end

      def registration_for(type, api)
        return unless defined?(::RecordingStudioApi)
        return unless ::RecordingStudioApi.respond_to?(:recordable_registration_for)

        ::RecordingStudioApi.recordable_registration_for(type, api: api)
      end
    end
  end
end
