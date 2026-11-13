# frozen_string_literal: true

module RecordingStudioAttachable
  module Api
    module OpenapiOverrides
      GENERIC = {
        create_upload: AttachmentActions::CREATE_UPLOAD_OPENAPI,
        attach: AttachmentActions::ATTACH_OPENAPI,
        import_attachment: AttachmentActions::IMPORT_ATTACHMENT_OPENAPI
      }.freeze

      class << self
        def assign(type:, action:, title: nil, summary: nil, description: nil)
          name = normalized_action!(action)
          overlay = { title: title, summary: summary, description: description }.compact
          raise ArgumentError, "override_openapi needs title, summary, or description" if overlay.empty?

          table[type.to_s][name] = overlay
        end

        def for(type:, action:)
          name = action.to_sym
          generic = GENERIC.fetch(name) { raise ArgumentError, "Unknown Attachable action #{action.inspect}" }
          generic.merge(table.dig(type.to_s, name) || {})
        end

        def clear!
          table.clear
        end

        private

        def table
          @table ||= Hash.new { |rows, type| rows[type] = {} }
        end

        def normalized_action!(action)
          name = action.to_sym
          return name if GENERIC.key?(name)

          raise ArgumentError, "Unknown Attachable action #{action.inspect}"
        end
      end
    end
  end
end
