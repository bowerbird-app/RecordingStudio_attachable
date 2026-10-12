# frozen_string_literal: true

require "json"
require "net/http"
require "uri"

module RecordingStudioAttachable
  module Dropbox
    # rubocop:disable Metrics/MethodLength, Metrics/AbcSize
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

        RecordingStudioAttachable::RemoteFile.new(
          uri: URI("#{CONTENT_ROOT}/2/files/download"),
          http_method: :post,
          headers: {
            "Authorization" => "Bearer #{access_token}",
            "Dropbox-API-Arg" => { path: file_id }.to_json
          },
          filename: metadata.fetch("name"),
          content_type: dropbox_content_type(metadata),
          byte_size: metadata["size"],
          external_id: metadata["id"] || file_id,
          allowed_hosts: ALLOWED_HOSTS,
          name: selection_value(selection, :name).presence || metadata.fetch("name"),
          description: selection_value(selection, :description)
        )
      end

      private

      attr_reader :access_token

      def get_metadata(file_id)
        post_json("/2/files/get_metadata", path: file_id)
      end

      def dropbox_content_type(_metadata)
        "application/octet-stream"
      end

      def normalized_file_id(selection)
        raise Error, "Dropbox imports require a file id from the Dropbox API" if client_supplied_url?(selection)

        raw = selection_value(selection, :id).to_s.strip
        raise Error, "Select a Dropbox file to import" if raw.blank?
        raise Error, "Dropbox imports require a file id from the Dropbox API" if raw.match?(/\Ahttps?:/i)

        raw.start_with?("id:") ? raw : "id:#{raw}"
      end

      def client_supplied_url?(selection)
        %w[url link download_url downloadUrl href].any? { |key| selection_value(selection, key).present? } &&
          selection_value(selection, :id).blank?
      end

      def selection_value(selection, *keys)
        hash = selection.respond_to?(:to_h) ? selection.to_h : {}
        keys.lazy.map { |key| hash[key.to_s] || hash[key] }.find(&:present?)
      end

      def post_json(path, payload)
        uri = URI("#{API_ROOT}#{path}")
        request = Net::HTTP::Post.new(uri)
        request["Authorization"] = "Bearer #{access_token}"
        request["Content-Type"] = "application/json"
        request.body = payload.to_json

        response = Net::HTTP.start(uri.host, uri.port, use_ssl: true) do |http|
          http.request(request)
        end

        body = parse_json(response.body)
        raise request_error(response, body) unless response.is_a?(Net::HTTPSuccess)

        body
      end

      def parse_json(body)
        JSON.parse(body.to_s)
      rescue JSON::ParserError
        {}
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
    # rubocop:enable Metrics/MethodLength, Metrics/AbcSize
  end
end
