# frozen_string_literal: true

module RecordingStudioAttachable
  module Adapter
    module Configurable
      def merge!(attributes)
        return self unless attributes.respond_to?(:each)

        attributes.each do |key, value|
          setter = "#{key}="
          public_send(setter, value) if respond_to?(setter)
        end

        self
      end

      def enabled?
        !!enabled
      end
    end
  end
end
