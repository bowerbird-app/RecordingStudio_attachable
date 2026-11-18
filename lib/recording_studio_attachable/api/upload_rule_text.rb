# frozen_string_literal: true

module RecordingStudioAttachable
  module Api
    module UploadRuleText
      EXAMPLE = "such as a PDF, an image, or a document"
      EXAMPLES = {
        "image/*" => "an image",
        "image/svg+xml" => "an SVG",
        "application/pdf" => "a PDF",
        "text/plain" => "a text file"
      }.freeze

      module_function

      def description_for(type, template)
        template.to_s
                .sub(EXAMPLE, "such as #{phrase(examples_for(types_for(type)))}")
                .sub(AttachmentCopy::Text::LIMITS, limits_paragraph(type))
      end

      def content_type(type)
        types = types_for(type)
        [
          "The file type, such as #{content_example(types)}. Required.",
          "This record allows #{phrase(types)}.",
          svg_sentence(types)
        ].compact.join(" ")
      end

      def byte_size(type)
        "The file size in bytes. Required. Use zero or more. #{size_sentence(UploadRules.value(type, :max_file_size))}"
      end

      def attachments(type)
        "#{AttachmentCopy::Fields::ATTACHMENTS_LEAD}#{batch_sentence(UploadRules.value(type, :max_file_count))}"
      end

      def limits_paragraph(type)
        [
          "This record allows #{phrase(types_for(type))}.",
          svg_sentence(types_for(type)),
          size_sentence(UploadRules.value(type, :max_file_size)),
          batch_sentence(UploadRules.value(type, :max_file_count)),
          "Allowed kinds are #{phrase(kinds_for(type))}.",
          pixel_sentence
        ].compact.join(" ")
      end

      def types_for(type)
        Array(UploadRules.value(type, :allowed_content_types))
      end

      def kinds_for(type)
        Array(UploadRules.value(type, :enabled_attachment_kinds)).map(&:to_s)
      end

      def examples_for(types)
        types.map { |pattern| EXAMPLES.fetch(pattern.to_s.downcase.strip, pattern.to_s) }.uniq
      end

      def content_example(types)
        return "image/svg+xml" if named_svg?(types)
        return "image/png" if types.any? { |pattern| pattern.to_s.downcase.start_with?("image/") }

        types.first.to_s
      end

      def svg_sentence(types)
        if named_svg?(types)
          "image/svg+xml is allowed because it is named in the allow list. image/* does not include image/svg+xml."
        elsif types.any? { |pattern| pattern.to_s.downcase.strip == "image/*" }
          "image/* does not include image/svg+xml."
        end
      end

      def named_svg?(types)
        types.any? { |pattern| pattern.to_s.downcase.strip == "image/svg+xml" }
      end

      def size_sentence(bytes)
        return "There is no size cap." if bytes.blank?

        "The size cap is #{size_label(bytes)}."
      end

      def size_label(bytes)
        megabytes = bytes.to_f / 1.megabyte
        return "#{megabytes.round} MB" if (megabytes - megabytes.round).abs < 0.001 && megabytes >= 1

        "#{bytes} bytes"
      end

      def batch_sentence(count)
        return "A batch has no file cap." if count.blank?

        "A batch can include up to #{count} files."
      end

      def pixel_sentence
        pixels = grouped(RecordingStudioAttachable.configuration.max_image_pixels)
        side = grouped(RecordingStudioAttachable.configuration.max_image_longest_side)
        "An image over #{pixels} pixels, or over #{side} pixels on the longest side, is refused."
      end

      def grouped(number)
        number.to_i.to_s.gsub(/(\d)(?=(\d{3})+\z)/, '\\1,')
      end

      def phrase(items)
        words = Array(items).map(&:to_s).reject(&:empty?)
        case words.length
        when 0 then "none"
        when 1 then words[0]
        when 2 then "#{words[0]} and #{words[1]}"
        else "#{words[0..-2].join(', ')}, and #{words[-1]}"
        end
      end
    end
  end
end
