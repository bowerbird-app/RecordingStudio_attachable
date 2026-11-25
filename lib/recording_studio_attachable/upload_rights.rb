# frozen_string_literal: true

module RecordingStudioAttachable
  # MCP/API upload confirmation. Browser direct uploads never call this.
  module UploadRights
    QUESTION = "Do you confirm you have the right to upload this image or file?"
    FIELD_DESCRIPTION =
      "Ask the user this exact question and send true only if they say yes: \"#{QUESTION}\"".freeze
    REFUSED = "Upload refused: you must confirm you have the right to upload this image or file."
    CONFIRMED = "rights_confirmed"
    CONFIRMED_AT = "rights_confirmed_at"
    CONFIRMED_BY = "rights_confirmed_by"

    module_function

    def require!(value)
      raise ArgumentError, REFUSED unless value == true
    end

    def field
      { "type" => "boolean", "description" => FIELD_DESCRIPTION }
    end

    def stamp(actor, at: Time.current.utc)
      {
        CONFIRMED => true,
        CONFIRMED_AT => at.iso8601,
        CONFIRMED_BY => actor_ref(actor)
      }
    end

    def attachment_attributes(blob, **explicit)
      return explicit_attributes(explicit) if explicit.key?(:rights_confirmed_at) || explicit.key?(:rights_confirmed_by)

      meta = blob_metadata(blob)
      return { rights_confirmed_at: nil, rights_confirmed_by: nil } unless confirmed?(meta)

      {
        rights_confirmed_at: parse_time(meta[CONFIRMED_AT]),
        rights_confirmed_by: meta[CONFIRMED_BY].presence
      }
    end

    def chatgpt_client(source)
      name = client_name(source)
      return if name.blank?

      /openai|chatgpt/i.match?(name)
    end

    def client_name(source)
      return if source.nil?
      return source.to_s.strip.presence if source.is_a?(String)
      return hash_name(source) if source.is_a?(Hash)

      object_name(source)
    end

    def actor_ref(actor)
      return actor.to_global_id.to_s if actor.respond_to?(:to_global_id)
      return "#{actor.class.name}/#{actor.id}" if actor.respond_to?(:id) && !actor.id.nil?

      actor.to_s
    end

    def blob_metadata(blob)
      blob.respond_to?(:metadata) ? blob.metadata.to_h.stringify_keys : {}
    end

    def confirmed?(meta)
      value = meta[CONFIRMED]
      value == true || value.to_s == "true"
    end

    def parse_time(value)
      return if value.blank?
      return value if value.respond_to?(:to_time) && !value.is_a?(String)

      Time.iso8601(value.to_s)
    rescue ArgumentError
      Time.zone ? Time.zone.parse(value.to_s) : Time.parse(value.to_s)
    end

    def explicit_attributes(explicit)
      {
        rights_confirmed_at: explicit[:rights_confirmed_at],
        rights_confirmed_by: explicit[:rights_confirmed_by]
      }
    end

    def hash_name(source)
      info = source[:clientInfo] || source["clientInfo"] || source[:client_info] || source["client_info"] || source
      return unless info.is_a?(Hash)

      (info[:name] || info["name"]).to_s.strip.presence
    end

    def object_name(source)
      %i[client_info mcp_client_info clientInfo].each do |method_name|
        next unless source.respond_to?(method_name)

        name = client_name(source.public_send(method_name))
        return name if name.present?
      end

      nil
    end
    private_class_method :actor_ref, :blob_metadata, :confirmed?, :parse_time, :explicit_attributes,
                         :hash_name, :object_name
  end
end
