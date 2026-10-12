# frozen_string_literal: true

require "marcel"
require "net/http"
require "uri"

module RecordingStudioAttachable
  module Dropbox
    class Client
      class Error < RecordingStudioAttachable::Error; end
      class UnauthorizedError < Error; end

      API_ROOT = "https://api.dropboxapi.com"
      CONTENT_ROOT = "https://content.dropboxapi.com"
      ALLOWED_HOSTS = %w[api.dropboxapi.com content.dropboxapi.com].freeze

      def initialize(access_token:)
        @access_token = access_token
      end

      def resolve(selection)
        file_id = normalized_file_id(selection)
        metadata = get_metadata(file_id)
        raise Error, "Dropbox folders cannot be imported" if metadata[".tag"] == "folder"

        download_remote_file(file_id, metadata, selection)
      end

      private

      attr_reader :access_token

      def get_metadata(file_id)
        post_json("/2/files/get_metadata", path: file_id)
      end

      def download_remote_file(file_id, metadata, selection)
        RecordingStudioAttachable::RemoteFile.new(**download_attributes(file_id, metadata, selection))
      end

      def download_attributes(file_id, metadata, selection)
        download_location(file_id, metadata).merge(
          name: Adapter::Selection.value(selection, :name).presence || metadata.fetch("name"),
          description: Adapter::Selection.value(selection, :description)
        )
      end

      def download_location(file_id, metadata)
        {
          uri: URI("#{CONTENT_ROOT}/2/files/download"),
          http_method: :post,
          headers: download_headers(file_id),
          allowed_hosts: ALLOWED_HOSTS
        }.merge(file_identity(file_id, metadata))
      end

      def file_identity(file_id, metadata)
        filename = metadata.fetch("name")
        {
          filename: filename,
          content_type: content_type_for(filename),
          byte_size: metadata["size"],
          external_id: metadata["id"] || file_id
        }
      end

      def content_type_for(filename)
        Marcel::MimeType.for(name: filename)
      end

      def download_headers(file_id)
        {
          "Authorization" => "Bearer #{access_token}",
          "Dropbox-API-Arg" => { path: file_id }.to_json
        }
      end

      def normalized_file_id(selection)
        raise Error, "Dropbox imports require a file id from the Dropbox API" if client_supplied_url?(selection)

        raw = Adapter::Selection.value(selection, :id).to_s.strip
        raise Error, "Select a Dropbox file to import" if raw.blank?
        raise Error, "Dropbox imports require a file id from the Dropbox API" if raw.match?(/\Ahttps?:/i)

        raw.start_with?("id:") ? raw : "id:#{raw}"
      end

      def client_supplied_url?(selection)
        %w[url link download_url downloadUrl href].any? { |key| Adapter::Selection.value(selection, key).present? } &&
          Adapter::Selection.value(selection, :id).blank?
      end

      def post_json(path, payload)
        uri = URI("#{API_ROOT}#{path}")
        response = start_json_post(uri, payload)
        body = RecordingStudioAttachable::JsonBody.parse(response.body)
        raise request_error(response, body) unless response.is_a?(Net::HTTPSuccess)

        body
      end

      def start_json_post(uri, payload)
        request = Net::HTTP::Post.new(uri)
        request["Authorization"] = "Bearer #{access_token}"
        request["Content-Type"] = "application/json"
        request.body = payload.to_json
        Net::HTTP.start(uri.host, uri.port, **RecordingStudioAttachable::SafeRemoteFetch.tls_start_options) do |http|
          http.request(request)
        end
      end

      def request_error(response, body)
        message = body["error_summary"].presence || body.dig("error", ".tag").presence || fallback_error_message(response)
        return UnauthorizedError.new(message) if response.code.to_i == 401

        Error.new(message)
      end

      def fallback_error_message(response)
        status = response.code.to_s.presence || "unknown"
        snippet = response.body.to_s.squish.truncate(200)
        details = snippet.presence || "no response body"

        "Dropbox request failed (HTTP #{status}): #{details}"
      end
    end
  end
end
