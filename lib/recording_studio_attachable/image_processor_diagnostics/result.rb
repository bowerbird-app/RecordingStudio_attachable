# frozen_string_literal: true

module RecordingStudioAttachable
  class ImageProcessorDiagnostics
    class Result
      attr_reader :processor, :error, :installation_help, :stage

      def initialize(success:, processor:, error: nil, installation_help: nil, stage: nil)
        @success = success
        @processor = processor
        @error = error
        @installation_help = installation_help
        @stage = stage
      end

      def success?
        @success
      end
    end

    class InstallationHelp
      def initialize(processor, reason)
        @processor = processor
        @reason = reason
      end

      def call
        <<~HELP
          RecordingStudioAttachable could not use the configured Active Storage
          image processor.

          Configured processor: #{processor || 'not configured'}
          Reason: #{reason}

          #{installation_instructions}

          Then rerun:

            bin/rails generate recording_studio_attachable:install
        HELP
      end

      private

      attr_reader :processor, :reason

      def installation_instructions
        return vips_instructions if processor == :vips
        return mini_magick_instructions if processor == :mini_magick

        <<~HELP.chomp
          Configure `config.active_storage.variant_processor` as `:vips` or `:mini_magick`,
          then install its Ruby integration and native image-processing library.
        HELP
      end

      def vips_instructions
        <<~HELP.chomp
          Install the Ruby integration (`gem "image_processing"`) and libvips:

            Debian/Ubuntu: apt-get install libvips-tools
            macOS:         brew install vips
            Alpine:        apk add vips
        HELP
      end

      def mini_magick_instructions
        <<~HELP.chomp
          Install the Ruby integration (`gem "image_processing"`) and ImageMagick:

            Debian/Ubuntu: apt-get install imagemagick
            macOS:         brew install imagemagick
            Alpine:        apk add imagemagick
        HELP
      end
    end
  end
end
