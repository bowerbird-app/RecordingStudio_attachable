# frozen_string_literal: true

require_relative "image_size"

module RecordingStudioAttachable
  # Pixel caps for an image. Upload refuses an over-cap file. Variant work
  # skips one. A declared size is enough, so the pixels are not decoded.
  module ImageLimits
    # I18n interpolates %{name}. These are not Kernel format tokens.
    # rubocop:disable Style/FormatStringToken
    REFUSAL = "This image is too big. Keep it under %{pixels} pixels, " \
              "and under %{side} pixels on the longest side."
    # rubocop:enable Style/FormatStringToken

    module_function

    def over_cap?(blob, capability_options: {})
      size = ImageSize.for(blob)
      return false unless size && raster_image?(blob)

      !within_caps?(size, caps_for(capability_options))
    end

    def allow_variants?(blob, capability_options: {})
      return true unless raster_image?(blob)

      size = ImageSize.for(blob)
      return true unless size

      within_caps?(size, caps_for(capability_options))
    end

    def refuse!(blob, capability_options: {})
      return unless over_cap?(blob, capability_options: capability_options)

      StorageLimit.discard_unattached!([blob])
      raise ArgumentError, refusal_message(capability_options)
    end

    def refusal_message(capability_options = {})
      caps = caps_for(capability_options)
      Copy.t(
        "errors.image_too_large",
        pixels: delimited(caps[:max_pixels]),
        side: delimited(caps[:max_longest_side]),
        default: REFUSAL
      )
    end

    def block_untrusted_loaders!(library = ImageSize.vips_library)
      return unless library.respond_to?(:block_untrusted)
      return unless vips_at_least?(library, 8, 13)

      library.block_untrusted(true)
    rescue StandardError
      nil
    end

    def caps_for(capability_options)
      options = capability_options.to_h.symbolize_keys
      config = RecordingStudioAttachable.configuration
      {
        max_pixels: count(options.fetch(:max_image_pixels) { config.max_image_pixels }),
        max_longest_side: count(options.fetch(:max_image_longest_side) { config.max_image_longest_side })
      }
    end

    def raster_image?(blob)
      type = content_type(blob)
      type.start_with?("image/") && type != "image/svg+xml"
    end

    def within_caps?(size, caps)
      width, height = size
      return false if caps[:max_pixels] && (width * height) > caps[:max_pixels]
      return false if caps[:max_longest_side] && [width, height].max > caps[:max_longest_side]

      true
    end

    def content_type(blob)
      type = blob.respond_to?(:content_type) ? blob.content_type.to_s.downcase : ""
      type = type.split(";").first.to_s.strip
      type == "image/jpg" ? "image/jpeg" : type
    end

    def vips_at_least?(library, major, minor)
      return false unless library.respond_to?(:version)

      current_major = library.version(0).to_i
      current_minor = library.version(1).to_i
      current_major > major || (current_major == major && current_minor >= minor)
    end

    def count(value)
      number = Integer(value)
      number.positive? ? number : nil
    rescue ArgumentError, TypeError
      nil
    end

    def delimited(number)
      number.to_i.to_fs(:delimited)
    end
  end
end
