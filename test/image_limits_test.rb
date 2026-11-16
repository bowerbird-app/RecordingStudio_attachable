# frozen_string_literal: true

require "test_helper"
require "stringio"
require_relative "support/oversized_png"
require_relative "../app/services/recording_studio_attachable/services/application_service"

module RecordingStudioAttachable
  class ImageLimitsTest < Minitest::Test
    def setup
      @configuration = RecordingStudioAttachable.configuration
      @pixels = @configuration.max_image_pixels
      @side = @configuration.max_image_longest_side
    end

    def teardown
      @configuration.max_image_pixels = @pixels
      @configuration.max_image_longest_side = @side
    end

    def test_a_png_header_answers_the_size_without_opening_vips
      blob = PathBlob.new(OversizedPng.bytes(20_000, 1))

      ImageSize.stub(:vips_size, ->(*) { flunk "vips opened the file" }) do
        assert_equal [20_000, 1], ImageSize.for(blob)
      end
    end

    def test_png_gif_and_jpeg_headers_report_size_without_a_pixel_buffer
      assert_equal [10_000, 10_000], ImageHeader.dimensions(OversizedPng.bytes(10_000, 10_000))
      gif = +"GIF89a"
      gif << [12, 8].pack("v2") << "rest"
      assert_equal [12, 8], ImageHeader.dimensions(gif)
      assert_equal [6_400, 4_800], ImageHeader.dimensions(jpeg_with_size(6_400, 4_800))
      assert_nil ImageHeader.dimensions("not an image")
    end

    def test_a_declared_size_over_either_cap_is_refused_and_an_equal_size_is_allowed
      wide = blob_for(OversizedPng.bytes(12_001, 1), "image/png")
      exact = blob_for(OversizedPng.bytes(12_000, 1), "image/png")
      pixels = blob_for(OversizedPng.bytes(10_000, 10_000), "image/png")

      assert ImageLimits.over_cap?(wide)
      assert_not ImageLimits.over_cap?(exact)
      assert ImageLimits.over_cap?(pixels)
      assert_not ImageLimits.allow_variants?(wide)
      assert ImageLimits.allow_variants?(exact)
    end

    def test_a_format_without_a_container_header_uses_a_sequential_vips_read
      blob = FormatBlob.new("image/webp")
      library = sequential_vips(width: 30_000, height: 2)

      ImageSize.stub(:vips_library, library) do
        assert ImageLimits.over_cap?(blob)
      end
      assert_equal :sequential, library.access
      assert_equal "/tmp/wide.webp", library.path
    end

    def test_svg_pdf_and_an_unreadable_image_are_not_refused
      svg = blob_for("<svg></svg>", "image/svg+xml")
      pdf = blob_for("%PDF-1.4", "application/pdf")
      heic = blob_for("not a header", "image/heic")

      assert_not ImageLimits.over_cap?(svg)
      assert_not ImageLimits.over_cap?(pdf)
      assert_not ImageLimits.over_cap?(heic)
      assert ImageLimits.allow_variants?(heic)
    end

    def test_analyzed_metadata_is_used_and_an_unanalyzed_blob_is_not_decoded_for_it
      analyzed = blob_for("unused", "image/png", metadata: { "width" => 50_000, "height" => 50_000 }, analyzed: true)
      waiting = blob_for(OversizedPng.bytes(8, 8), "image/png", metadata: { "width" => 50_000, "height" => 1 }, analyzed: false)

      assert ImageLimits.over_cap?(analyzed)
      assert_not ImageLimits.over_cap?(waiting)
    end

    def test_capability_options_override_both_caps_and_the_message_states_them
      photo = blob_for(OversizedPng.bytes(80, 80), "image/png")
      options = { max_image_pixels: 100, max_image_longest_side: 50 }

      assert ImageLimits.over_cap?(photo, capability_options: options)
      message = ImageLimits.refusal_message(options)
      assert_includes message, "100"
      assert_includes message, "50"
      assert_includes message, "too big"
    end

    def test_validate_blob_purges_an_over_cap_image_and_keeps_a_normal_one
      bomb = blob_for(OversizedPng.bytes(13_000, 1), "image/png")
      photo = blob_for(OversizedPng.bytes(8, 8, valid: true), "image/png")
      service = Probe.new

      error = assert_raises(ArgumentError) { service.check(bomb) }
      assert_includes error.message, "12,000"
      assert_equal true, bomb.purged

      assert_nil service.check(photo)
      assert_equal false, photo.purged
    end

    def test_image_caps_reject_a_blank_or_non_positive_value
      assert_raises(ArgumentError) { @configuration.max_image_pixels = 0 }
      assert_raises(ArgumentError) { @configuration.max_image_longest_side = "many" }
    end

    def test_block_untrusted_runs_only_when_the_library_can_and_is_new_enough
      library = FakeVips.new(major: 8, minor: 15)
      ImageLimits.block_untrusted_loaders!(library)
      assert_equal true, library.blocked

      old = FakeVips.new(major: 8, minor: 12)
      ImageLimits.block_untrusted_loaders!(old)
      assert_nil old.blocked

      ImageLimits.block_untrusted_loaders!(nil)
    end

    private

    def sequential_vips(width:, height:)
      image = Struct.new(:width, :height).new(width, height)
      library = Module.new
      image_class = Class.new do
        define_singleton_method(:new_from_file) do |path, access:|
          library.access = access
          library.path = path
          image
        end
      end
      library.const_set(:Image, image_class)
      library.define_singleton_method(:access) { @access }
      library.define_singleton_method(:access=) { |value| @access = value }
      library.define_singleton_method(:path) { @path }
      library.define_singleton_method(:path=) { |value| @path = value }
      library
    end

    def jpeg_with_size(width, height)
      frame = [11].pack("n") + [8].pack("C") + [height, width].pack("n2") + [1, 1, 0x11, 0].pack("C4")
      "\xFF\xD8\xFF\xC0".b + frame + "\xFF\xD9".b
    end

    def blob_for(bytes, content_type, metadata: {}, analyzed: true)
      HeaderBlob.new(bytes: bytes, content_type: content_type, metadata: metadata, analyzed: analyzed)
    end

    class FormatBlob
      def initialize(content_type)
        @content_type = content_type
      end

      attr_reader :content_type

      def analyzed?
        false
      end

      def metadata
        {}
      end

      def open
        yield HeaderFile.new("RIFF", path: "/tmp/wide.webp")
      end
    end

    class PathBlob
      def initialize(bytes)
        @bytes = bytes
      end

      def content_type
        "image/png"
      end

      def analyzed?
        false
      end

      def metadata
        {}
      end

      def open
        yield HeaderFile.new(@bytes)
      end
    end

    class HeaderFile
      def initialize(bytes, path: "/tmp/wide.png")
        @bytes = bytes
        @path = path
      end

      attr_reader :path

      def read(length = nil)
        length ? @bytes.byteslice(0, length) : @bytes
      end
    end

    class HeaderBlob
      attr_reader :content_type, :metadata
      attr_accessor :purged

      def initialize(bytes:, content_type:, metadata:, analyzed:)
        @bytes = bytes
        @content_type = content_type
        @metadata = metadata
        @analyzed = analyzed
        @purged = false
      end

      def byte_size
        @bytes.bytesize
      end

      def analyzed?
        @analyzed
      end

      def persisted?
        true
      end

      def attachments
        nil
      end

      def open
        yield StringIO.new(@bytes)
      end

      def purge
        @purged = true
      end
    end

    class Probe < RecordingStudioAttachable::Services::ApplicationService
      def check(blob)
        send(:validate_blob!, blob, capability_options: {})
      end

      private

      def perform; end
    end

    class FakeVips
      attr_reader :blocked

      def initialize(major:, minor:)
        @major = major
        @minor = minor
      end

      def version(index)
        index.zero? ? @major : @minor
      end

      def block_untrusted(state)
        @blocked = state
      end
    end
  end
end
