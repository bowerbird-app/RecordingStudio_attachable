# frozen_string_literal: true

module RecordingStudioAttachable
  class RemoteFile
    attr_reader :uri, :headers, :http_method, :body, :filename, :content_type, :byte_size,
                :external_id, :external_url, :allowed_hosts, :name, :description

    def initialize(uri:, allowed_hosts:, filename:, content_type:, headers: {}, http_method: :get,
                   body: nil, byte_size: nil, external_id: nil, external_url: nil, name: nil, description: nil)
      @uri = uri.is_a?(URI) ? uri : URI.parse(uri.to_s)
      @headers = headers.to_h
      @http_method = http_method.to_s.upcase
      @body = body
      @filename = filename
      @content_type = content_type
      @byte_size = byte_size&.to_i
      @byte_size = nil if @byte_size&.zero?
      @external_id = external_id
      @external_url = external_url
      @allowed_hosts = Array(allowed_hosts)
      @name = name
      @description = description
    end
  end
end
