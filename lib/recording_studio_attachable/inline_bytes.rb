# frozen_string_literal: true

require "base64"

module RecordingStudioAttachable
  # Decoded size of an inline upload, checked before the full decode.
  module InlineBytes
    DATA_PREFIX = "data:"
    BASE64_PATTERN = %r{\A[A-Za-z0-9+/]*={0,2}\z}
    TOO_BIG = "Inline upload exceeds inline_upload_max_bytes"
    BAD = "data is not valid base64"

    module_function

    def decode(data, cap:, inline_max:)
      encoded = payload(data, cap, inline_max)
      strict_decode(encoded)
    end

    def payload(data, cap, inline_max)
      text = data.to_s
      raise ArgumentError, message(cap + 1, inline_max) if text.bytesize > ceiling(cap)

      compact = body(text).gsub(/\s+/, "")
      raise ArgumentError, BAD unless compact.match?(BASE64_PATTERN) && compact.present?

      estimate = estimated_bytes(compact)
      raise ArgumentError, message(estimate, inline_max) if estimate > cap

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

    def message(estimate, inline_max)
      return TOO_BIG if estimate > inline_max

      "File exceeds maximum file size"
    end

    def strict_decode(encoded)
      Base64.strict_decode64(encoded)
    rescue ArgumentError
      raise ArgumentError, BAD
    end
    private_class_method :payload, :ceiling, :body, :estimated_bytes, :message, :strict_decode
  end
end
