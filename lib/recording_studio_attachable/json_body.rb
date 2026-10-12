# frozen_string_literal: true

require "json"

module RecordingStudioAttachable
  module JsonBody
    module_function

    def parse(body)
      JSON.parse(body.to_s)
    rescue JSON::ParserError
      {}
    end
  end
end
