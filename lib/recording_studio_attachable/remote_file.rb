# frozen_string_literal: true

module RecordingStudioAttachable
  class RemoteFile
    attr_reader :uri, :headers, :http_method, :body, :filename, :content_type, :byte_size,
                :external_id, :external_url, :allowed_hosts, :name, :description

    def initialize(**attributes)
      assign_request(attributes)
      assign_file(attributes)
      assign_identity(attributes)
    end

    private

    def assign_request(attributes)
      raw_uri = attributes.fetch(:uri)
      @uri = raw_uri.is_a?(URI) ? raw_uri : URI.parse(raw_uri.to_s)
      @headers = attributes.fetch(:headers, {}).to_h
      @http_method = attributes.fetch(:http_method, :get).to_s.upcase
      @body = attributes[:body]
      @allowed_hosts = Array(attributes.fetch(:allowed_hosts))
    end

    def assign_file(attributes)
      @filename = attributes.fetch(:filename)
      @content_type = attributes.fetch(:content_type)
      size = attributes[:byte_size]&.to_i
      @byte_size = size&.zero? ? nil : size
    end

    def assign_identity(attributes)
      @external_id = attributes[:external_id]
      @external_url = attributes[:external_url]
      @name = attributes[:name]
      @description = attributes[:description]
    end
  end
end
