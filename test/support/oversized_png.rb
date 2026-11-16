# frozen_string_literal: true

require "zlib"

# Tiny PNGs with a declared size. A valid image is one white row, repeated.
# An invalid image keeps the header and an empty image body, so a test never
# commits a large file.
module OversizedPng
  module_function

  def bytes(width, height, valid: false, fill: 255)
    signature = [137, 80, 78, 71, 13, 10, 26, 10].pack("C*")
    header = chunk("IHDR", [width, height, 8, 2, 0, 0, 0].pack("N2C5"))
    pixels = valid ? chunk("IDAT", Zlib.deflate(filled_rows(width, height, fill))) : chunk("IDAT", Zlib.deflate(""))
    signature + header + pixels + chunk("IEND", "")
  end

  def chunk(type, data)
    [data.bytesize].pack("N") + type + data + [Zlib.crc32(type + data)].pack("N")
  end

  def filled_rows(width, height, fill)
    row = "\x00".b + (fill.chr.b * (width * 3))
    row * height
  end
end
