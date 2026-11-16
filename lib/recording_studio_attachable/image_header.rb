# frozen_string_literal: true

module RecordingStudioAttachable
  # Width and height from a container header. No pixel decode.
  module ImageHeader
    PNG_SIGNATURE = "\x89PNG\r\n\x1A\n".b
    JPEG_START = "\xFF\xD8".b
    SOF_MARKERS = ((0xC0..0xCF).to_a - [0xC4, 0xC8, 0xCC]).freeze

    module_function

    def dimensions(bytes)
      return if bytes.nil? || bytes.bytesize < 10

      png(bytes) || gif(bytes) || jpeg(bytes)
    end

    def png(bytes)
      return unless bytes.bytesize >= 24 && bytes.start_with?(PNG_SIGNATURE)
      return unless bytes.byteslice(12, 4) == "IHDR"

      pair(*bytes.byteslice(16, 8).unpack("N2"))
    end

    def gif(bytes)
      return unless bytes.start_with?("GIF87a", "GIF89a")

      pair(*bytes.byteslice(6, 4).unpack("v2"))
    end

    def jpeg(bytes)
      return unless bytes.start_with?(JPEG_START)

      JpegSize.new(bytes).find
    end

    def pair(width, height)
      return unless width.to_i.positive? && height.to_i.positive?

      [width.to_i, height.to_i]
    end

    class JpegSize
      def initialize(bytes)
        @bytes = bytes
        @offset = 2
        @size = nil
      end

      def find
        step until done?
        @size
      end

      private

      def done?
        @size || @offset + 4 >= @bytes.bytesize
      end

      def step
        return finish unless marker_prefix?

        marker = read_marker
        return finish if stop_marker?(marker)
        return if standalone_marker?(marker)

        length = segment_length
        return finish unless length

        read_sof(marker)
        @offset += length
      end

      def marker_prefix?
        @bytes.getbyte(@offset) == 0xFF
      end

      def read_marker
        @offset += 1 while @bytes.getbyte(@offset) == 0xFF
        marker = @bytes.getbyte(@offset)
        @offset += 1
        marker
      end

      def stop_marker?(marker)
        marker.nil? || marker == 0xD9 || marker == 0xDA
      end

      def standalone_marker?(marker)
        (0xD0..0xD7).cover?(marker) || marker == 0x01
      end

      def segment_length
        length = @bytes.byteslice(@offset, 2)&.unpack1("n")
        length if length && length >= 2
      end

      def finish
        @offset = @bytes.bytesize
      end

      def read_sof(marker)
        return unless SOF_MARKERS.include?(marker)
        return unless @offset + 7 < @bytes.bytesize

        height, width = @bytes.byteslice(@offset + 3, 4).unpack("n2")
        @size = ImageHeader.pair(width, height)
      end
    end
  end
end
