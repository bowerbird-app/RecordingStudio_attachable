# frozen_string_literal: true

module RecordingStudioAttachable
  class SafeRemoteFetch
    class SizeLimit
      def initialize(max_bytes)
        @max_bytes = max_bytes.nil? ? nil : Integer(max_bytes)
        return if unlimited?

        raise Error, "Maximum download size must be positive" unless @max_bytes.positive?
      end

      def unlimited?
        @max_bytes.nil?
      end

      def check!(bytes)
        return if unlimited? || bytes.nil?
        raise Error, "Remote file exceeds maximum file size" if bytes > @max_bytes
      end
    end
  end
end
