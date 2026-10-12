# frozen_string_literal: true

module RecordingStudioAttachable
  module Adapter
    module Selection
      module_function

      def value(selection, *keys)
        hash = selection.respond_to?(:to_h) ? selection.to_h : {}
        keys.lazy.map { |key| hash[key.to_s] || hash[key] }.find(&:present?)
      end

      def files(selections, extra_keys: {})
        Array(selections).filter_map do |selection|
          case selection
          when String
            selection.presence && { "id" => selection }
          when Hash
            hash_for(selection, extra_keys: extra_keys)
          end
        end.uniq
      end

      def from_attachments(attachments)
        Array(attachments).map { |payload| attachment_hash(payload) }
      end

      def hash_for(selection, extra_keys: {})
        id = value(selection, :id)
        return if id.blank?

        {
          "id" => id.to_s,
          "name" => value(selection, :name).to_s.presence,
          "description" => value(selection, :description).to_s.presence,
          "metadata" => metadata_for(selection)
        }.merge(extra_fields(selection, extra_keys)).compact
      end

      def metadata_for(selection)
        raw = value(selection, :metadata)
        raw.respond_to?(:to_h) ? raw.to_h.compact_blank : {}
      end

      def extra_fields(selection, extra_keys)
        extra_keys.each_with_object({}) do |(key, aliases), memo|
          memo[key.to_s] = value(selection, *Array(aliases).presence || key).to_s.presence
        end
      end

      def attachment_hash(payload)
        provider_payload = payload.fetch(:provider_payload, {}).to_h.stringify_keys
        provider_payload.merge(
          "name" => payload[:name],
          "description" => payload[:description],
          "metadata" => payload.fetch(:metadata, {}).to_h.except("provider", :provider)
        ).compact_blank
      end
    end
  end
end
