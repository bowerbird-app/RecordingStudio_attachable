# frozen_string_literal: true

module RecordingStudioAttachable
  module McpCopy
    # JSON Schema for ChatGPT's file object. The tool lists "file" in
    # openai/fileParams once the MCP gem can emit per-tool _meta.
    module FileField
      DESCRIPTION = "A file the user attached in ChatGPT. Send download_url and file_id. " \
                    "mime_type is only a hint. The bytes decide the stored type. file_name is the name to store."

      module_function

      def schema
        {
          "type" => "object",
          "description" => DESCRIPTION,
          "properties" => properties,
          "required" => %w[download_url file_id]
        }
      end

      def properties
        {
          "download_url" => string("Short-lived HTTPS address of the attached file. The server fetches it."),
          "file_id" => string("ChatGPT id for the attached file."),
          "mime_type" => string("Declared content type. The server checks the bytes and uses those."),
          "file_name" => string("File name to store. When omitted, the server uses a safe default.")
        }
      end

      def string(description)
        { "type" => "string", "description" => description }
      end
      private_class_method :properties, :string
    end
  end
end
