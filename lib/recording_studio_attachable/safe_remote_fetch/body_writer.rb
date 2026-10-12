# frozen_string_literal: true

require "tempfile"

module RecordingStudioAttachable
  class SafeRemoteFetch
    class BodyWriter
      def initialize(filename:, size_limit:, deadline:)
        @filename = filename
        @size_limit = size_limit
        @deadline = deadline
      end

      def write(response)
        tempfile = Tempfile.new(["recording-studio-attachable-fetch", File.extname(filename.to_s)])
        tempfile.binmode
        stream_chunks(response, tempfile)
        tempfile.flush
        tempfile.rewind
        tempfile
      rescue StandardError
        tempfile&.close!
        raise
      end

      private

      attr_reader :filename, :size_limit, :deadline

      def stream_chunks(response, tempfile)
        written = 0
        each_chunk(response) do |chunk|
          deadline.remaining
          written += chunk.bytesize
          size_limit.check!(written)
          tempfile.write(chunk)
        end
      end

      def each_chunk(response)
        raise Error, "Remote download body could not be streamed" unless response.respond_to?(:read_body)

        response.read_body { |chunk| yield chunk.to_s }
      end
    end
  end
end
