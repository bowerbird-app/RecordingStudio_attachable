# frozen_string_literal: true

require "base64"

module RecordingStudioAttachable
  # Decoded size of an inline upload, checked before the full decode.
  module InlineBytes
    DATA_PREFIX = "data:"
    BASE64_PATTERN = %r{\A[A-Za-z0-9+/]*={0,2}\z}
    BAD = "data is not valid base64. For a file attached in ChatGPT, send file. For a public image, send an https url."

    module_function

    def decode(data, cap:, inline_max:)
      encoded = payload(data, cap, inline_max)
      strict_decode(encoded)
    end

    def size_words(bytes)
      megabytes = bytes.to_f / 1.megabyte
      return "#{bytes.to_i} bytes" if megabytes < 0.1

      "#{format('%.1f', megabytes).sub(/\.0\z/, '')} MB"
    end

    def payload(data, cap, inline_max)
      text = data.to_s
      raise ArgumentError, too_big_message(rough_bytes(text), cap, inline_max) if text.bytesize > ceiling(cap)

      compact = body(text).gsub(/\s+/, "")
      raise ArgumentError, BAD unless compact.match?(BASE64_PATTERN) && compact.present?

      estimate = estimated_bytes(compact)
      raise ArgumentError, too_big_message(estimate, cap, inline_max) if estimate > cap

      compact
    end

    def ceiling(cap)
      ((cap + 2) * 4 / 3) + 256
    end

    def body(text)
      return text unless text.lstrip.start_with?(DATA_PREFIX)

      header, encoded = text.lstrip.split(",", 2)
      raise ArgumentError, BAD if encoded.nil? || !header.downcase.include?(";base64")

      encoded
    end

    def estimated_bytes(encoded)
      ((encoded.length * 3) / 4) - encoded.count("=")
    end

    def rough_bytes(text)
      encoded = text.lstrip
      encoded = encoded.split(",", 2).last.to_s if encoded.start_with?(DATA_PREFIX)
      estimated_bytes(encoded.gsub(/\s+/, ""))
    end

    def too_big_message(byte_size, cap, inline_max)
      size = size_words(byte_size)
      limit = size_words(cap)
      if cap < inline_max
        "This file is #{size}; this record accepts files up to #{limit}."
      else
        "This file is #{size}; data uploads can be up to #{limit}. Send a public https url for larger files."
      end
    end

    def strict_decode(encoded)
      Base64.strict_decode64(encoded)
    rescue ArgumentError
      raise ArgumentError, BAD
    end
    private_class_method :payload, :ceiling, :body, :estimated_bytes, :rough_bytes, :too_big_message, :strict_decode
  end
end
