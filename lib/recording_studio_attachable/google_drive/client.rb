# frozen_string_literal: true

require "json"
require "net/http"
require "stringio"
require "uri"

module RecordingStudioAttachable
  module GoogleDrive
    # rubocop:disable Metrics/ClassLength
    class Client
      class Error < RecordingStudioAttachable::Error; end
      class UnauthorizedError < Error; end

      EXPORT_MIME_TYPES = {
        "application/vnd.google-apps.document" => { content_type: "application/pdf", extension: ".pdf" },
        "application/vnd.google-apps.drawing" => { content_type: "image/png", extension: ".png" },
        "application/vnd.google-apps.presentation" => { content_type: "application/pdf", extension: ".pdf" },
        "application/vnd.google-apps.spreadsheet" => { content_type: "text/csv", extension: ".csv" }
      }.freeze

      API_ROOT = "https://www.googleapis.com/drive/v3"
      MAX_REDIRECTS = 5

      def initialize(access_token:)
        @access_token = access_token
      end

      def list_files(query: nil, page_token: nil, page_size: RecordingStudioAttachable.configuration.google_drive.page_size)
        get_json(
          "/files",
          fields: "nextPageToken,files(id,name,mimeType,size,modifiedTime,webViewLink)",
          includeItemsFromAllDrives: true,
          pageSize: page_size,
          pageToken: page_token,
          q: drive_query(query),
          supportsAllDrives: true
        )
      end

      def fetch_file(file_id, resource_key: nil)
        get_json(
          "/files/#{file_id}",
          fields: "id,name,mimeType,resourceKey,webViewLink",
          resourceKey: resource_key,
          supportsAllDrives: true
        )
      end

      def download_file(file)
        metadata = file.stringify_keys
        export = EXPORT_MIME_TYPES[metadata.fetch("mimeType")]
        request_params = {
          resourceKey: metadata["resourceKey"],
          supportsAllDrives: true
        }

        if export
          body = get_body(
            "/files/#{metadata.fetch('id')}/export",
            mimeType: export.fetch(:content_type),
            **request_params
          )
          return {
            io: StringIO.new(body),
            filename: append_extension(metadata.fetch("name"), export.fetch(:extension)),
            content_type: export.fetch(:content_type)
          }
        end

        body, content_type = get_binary("/files/#{metadata.fetch('id')}", alt: "media", **request_params)
        {
          io: StringIO.new(body),
          filename: metadata.fetch("name"),
          content_type: normalized_content_type(content_type) || metadata.fetch("mimeType")
        }
      end

      private

      attr_reader :access_token

      def drive_query(query)
        clauses = ["trashed = false", "mimeType != 'application/vnd.google-apps.folder'"]
        clauses << "name contains '#{query.to_s.gsub("'", "\\\\'")}'" if query.present?
        clauses.join(" and ")
      end

      def append_extension(filename, extension)
        filename.end_with?(extension) ? filename : "#{filename}#{extension}"
      end

      def normalized_content_type(value)
        value.to_s.split(";").first.presence
      end

      def get_json(path, params = {})
        response = perform_request(path, params: params)
        body = parse_json(response.body)
        raise request_error(response, body) unless response.is_a?(Net::HTTPSuccess)

        body
      end

      def get_body(path, params = {})
        response = perform_request(path, params: params)
        raise request_error(response, parse_json(response.body)) unless response.is_a?(Net::HTTPSuccess)

        response.body.to_s
      end

      def get_binary(path, params = {})
        response = perform_request(path, params: params)
        raise request_error(response, parse_json(response.body)) unless response.is_a?(Net::HTTPSuccess)

        [response.body.to_s, response["content-type"]]
      end

      def perform_request(path, params: {})
        uri = URI.join("#{API_ROOT}/", path.to_s.sub(%r{\A/+}, ""))
        compact_params = params.compact
        uri.query = URI.encode_www_form(compact_params) if compact_params.any?

        perform_get_request(uri, redirects_remaining: MAX_REDIRECTS)
      end

      def perform_get_request(uri, redirects_remaining:)
        raise Error, "Google Drive request redirected too many times" if redirects_remaining.negative?

        request = Net::HTTP::Get.new(uri)
        request["Authorization"] = "Bearer #{access_token}"

        Net::HTTP.start(uri.host, uri.port, use_ssl: true) do |http|
          response = http.request(request)
          return response unless response.is_a?(Net::HTTPRedirection)

          location = response["location"].to_s
          return response if location.blank?

          redirected_uri = URI.join(uri.to_s, location)
          perform_get_request(redirected_uri, redirects_remaining: redirects_remaining - 1)
        end
      end

      def parse_json(body)
        JSON.parse(body.to_s)
      rescue JSON::ParserError
        {}
      end

      def request_error(response, body)
        message = body.dig("error", "message").presence || body["error_description"].presence || fallback_error_message(response)
        return UnauthorizedError.new(message) if response.code.to_i == 401

        Error.new(message)
      end

      def fallback_error_message(response)
        status = response.code.to_s.presence || "unknown"
        snippet = response.body.to_s.squish.truncate(200)
        details = snippet.presence || "no response body"

        "Google Drive request failed (HTTP #{status}): #{details}"
      end
    end
    # rubocop:enable Metrics/ClassLength
  end
end
