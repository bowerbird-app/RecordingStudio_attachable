# frozen_string_literal: true

module RecordingStudioAttachable
  class SafeRemoteFetch
    class Deadline
      def initialize(seconds)
        @ends_at = Process.clock_gettime(Process::CLOCK_MONOTONIC) + seconds
      end

      def remaining
        left = @ends_at - Process.clock_gettime(Process::CLOCK_MONOTONIC)
        raise Error, "Remote download timed out" if left <= 0

        left
      end
    end
  end
end
