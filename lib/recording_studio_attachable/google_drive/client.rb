# frozen_string_literal: true

require "erb"
require "json"
require "net/http"
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
      ALLOWED_HOSTS = [
        "www.googleapis.com",
        "googleapis.com",
        "googleusercontent.com",
        "*.googleusercontent.com"
      ].freeze
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
          file_resource_path(file_id),
          fields: "id,name,mimeType,resourceKey,webViewLink,size",
          resourceKey: resource_key,
          supportsAllDrives: true
        )
      end

      def resolve(selection)
        metadata = fetch_file(
          selection_value(selection, :id),
          resource_key: selection_value(selection, :resource_key, :resourceKey)
        )
        remote_file_for(
          metadata.merge(
            "name" => selection_value(selection, :name).presence || metadata.fetch("name"),
            "description" => selection_value(selection, :description),
            "resourceKey" => metadata["resourceKey"] || selection_value(selection, :resource_key, :resourceKey)
          )
        )
      end

      def download_file(file)
        remote_file = remote_file_for(file.stringify_keys)
        fetched = RecordingStudioAttachable::SafeRemoteFetch.call(
          remote_file,
          max_bytes: RecordingStudioAttachable.configuration.max_file_size
        )
        {
          io: fetched.io,
          filename: remote_file.filename,
          content_type: fetched.content_type || remote_file.content_type
        }
      end

      def remote_file_for(metadata)
        export = EXPORT_MIME_TYPES[metadata.fetch("mimeType")]
        filename = export ? append_extension(metadata.fetch("name"), export.fetch(:extension)) : metadata.fetch("name")
        content_type = export ? export.fetch(:content_type) : metadata.fetch("mimeType")
        path = if export
                 "#{file_resource_path(metadata.fetch('id'))}/export"
               else
                 file_resource_path(metadata.fetch("id"))
               end
        params = {
          resourceKey: metadata["resourceKey"],
          supportsAllDrives: true
        }
        params[:mimeType] = export.fetch(:content_type) if export
        params[:alt] = "media" unless export

        RecordingStudioAttachable::RemoteFile.new(
          uri: request_uri(path, params),
          headers: { "Authorization" => "Bearer #{access_token}" },
          filename: filename,
          content_type: content_type,
          byte_size: metadata["size"],
          external_id: metadata.fetch("id"),
          external_url: metadata["webViewLink"],
          allowed_hosts: ALLOWED_HOSTS,
          name: metadata["name"],
          description: metadata["description"]
        )
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

      def file_resource_path(file_id)
        "/files/#{ERB::Util.url_encode(file_id.to_s)}"
      end

      def selection_value(selection, *keys)
        Adapter::Selection.value(selection, *keys)
      end

      def get_json(path, params = {})
        response = perform_request(path, params: params)
        body = parse_json(response.body)
        raise request_error(response, body) unless response.is_a?(Net::HTTPSuccess)

        body
      end

      def perform_request(path, params: {})
        perform_get_request(request_uri(path, params), redirects_remaining: MAX_REDIRECTS)
      end

      def request_uri(path, params)
        uri = URI.join("#{API_ROOT}/", path.to_s.sub(%r{\A/+}, ""))
        compact_params = params.compact
        uri.query = URI.encode_www_form(compact_params) if compact_params.any?
        uri
      end

      def perform_get_request(uri, redirects_remaining:)
        raise Error, "Google Drive request redirected too many times" if redirects_remaining.negative?
        raise Error, "Google Drive request must use HTTPS" unless uri.is_a?(URI::HTTPS)
        raise Error, "Google Drive request host is not allowed" unless json_host_allowed?(uri.host)

        request = Net::HTTP::Get.new(uri)
        request["Authorization"] = "Bearer #{access_token}"

        Net::HTTP.start(uri.host, uri.port, use_ssl: true) do |http|
          response = http.request(request)
          return response unless response.is_a?(Net::HTTPRedirection)

          location = response["location"].to_s
          return response if location.blank?

          redirected_uri = URI.join(uri.to_s, location)
          raise Error, "Google Drive request refused a cross-host redirect" if redirected_uri.host.to_s.downcase != uri.host.to_s.downcase

          perform_get_request(redirected_uri, redirects_remaining: redirects_remaining - 1)
        end
      end

      def json_host_allowed?(host)
        %w[www.googleapis.com googleapis.com].include?(host.to_s.downcase)
      end

      def parse_json(body)
        RecordingStudioAttachable::JsonBody.parse(body)
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
