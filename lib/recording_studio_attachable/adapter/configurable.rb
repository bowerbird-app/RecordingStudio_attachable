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

      private

      def valid_credential?(value, field)
        normalized = value.to_s.strip
        return false if normalized.blank?

        Array(self.class::PLACEHOLDER_PREFIXES[field]).exclude?(normalized)
      end
    end
  end
end
