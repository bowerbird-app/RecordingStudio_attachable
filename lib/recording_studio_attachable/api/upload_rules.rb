# frozen_string_literal: true

require_relative "upload_rule_text"

module RecordingStudioAttachable
  module Api
    module UploadRules
      RULE_KEYS = %i[allowed_content_types max_file_size max_file_count enabled_attachment_kinds].freeze
      FIELD_NAMES = {
        create_upload: %i[content_type byte_size],
        attach: %i[attachments]
      }.freeze

      module_function

      def apply(type, action, openapi)
        return openapi unless customized?(type)

        openapi
          .merge(description: UploadRuleText.description_for(type, openapi[:description]))
          .merge(field_overlay(type, action))
      end

      def limits_paragraph(type)
        UploadRuleText.limits_paragraph(type)
      end

      def customized?(type)
        RULE_KEYS.any? { |key| options_for(type).key?(key) }
      end

      def field_overlay(type, action)
        properties = field_descriptions(type, action)
        return {} if properties.empty?

        { request_body: { content: { "application/json" => { schema: { properties: properties } } } } }
      end

      def field_descriptions(type, action)
        Array(FIELD_NAMES[action]).to_h { |name| [name, { description: UploadRuleText.public_send(name, type) }] }
      end

      def options_for(type)
        return {} unless defined?(RecordingStudio) && RecordingStudio.respond_to?(:capability_options)

        raw = RecordingStudio.capability_options(:attachable, for_type: type.to_s)
        return {} if raw.blank?

        raw.respond_to?(:symbolize_keys) ? raw.symbolize_keys : raw.to_h
      end

      def value(type, key)
        options = options_for(type)
        return options[key] if options.key?(key)

        RecordingStudioAttachable.configuration.public_send(key)
      end
    end
  end
end
