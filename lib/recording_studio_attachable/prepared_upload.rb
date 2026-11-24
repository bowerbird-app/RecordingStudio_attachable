# frozen_string_literal: true

require "stringio"
require_relative "inline_bytes"

module RecordingStudioAttachable
  # Bytes already in hand, stored as the same tagged unattached blob a direct
  # upload ticket would have produced after the client PUT.
  module PreparedUpload
    INLINE_TOO_BIG = InlineBytes::TOO_BIG
    BAD_BASE64 = InlineBytes::BAD

    module_function

    def fetch(recording:, actor:, url:, filename: nil)
      ready!(recording, actor)
      remote = remote_file(url, filename)
      fetched = SafeRemoteFetch.call(remote, max_bytes: file_cap(recording))
      ticket_for(recording, actor, fetched.io, remote.filename, fetched.content_type)
    ensure
      SafeRemoteFetch.close_io(fetched&.io)
    end

    def inline(recording:, actor:, data:, filename:)
      raise ArgumentError, "filename is required" if filename.blank?

      ready!(recording, actor)
      ticket_for(recording, actor, StringIO.new(decoded(data, recording)), filename, "application/octet-stream")
    end

    def ready!(recording, actor)
      authorize!(recording, actor)
      DirectUpload.ensure_pending!(recording, actor)
    end

    def ticket_for(recording, actor, io, filename, declared_type)
      blob = DirectUpload.prepare_from_io!(
        recording: recording, actor: actor, io: io, filename: filename, declared_type: declared_type
      )
      DirectUpload.ticket(blob)
    end

    def authorize!(recording, actor)
      raise ArgumentError, "Actor is required" if actor.blank?

      Authorization.authorize!(action: :upload, actor: actor, recording: recording)
      return unless Authorization::TrashVisibility.owner_trashed?(recording)

      raise Authorization::OwnerUnavailableError, denial(recording)
    end

    def denial(recording)
      type = recording.respond_to?(:recordable_type) ? recording.recordable_type : recording.class.name
      "Not authorized to upload attachments for #{type}"
    end

    def remote_file(url, filename)
      uri = parse_url(url)
      RemoteFile.new(
        uri: uri,
        filename: chosen_filename(filename, uri),
        content_type: "application/octet-stream",
        allowed_hosts: configuration.import_allowed_hosts
      )
    end

    def parse_url(url)
      URI.parse(url.to_s)
    rescue URI::InvalidURIError
      raise ArgumentError, "url must be an HTTPS URL"
    end

    def chosen_filename(filename, uri)
      filename.to_s.strip.presence || File.basename(uri.path.presence || "download")
    end

    def decoded(data, recording)
      InlineBytes.decode(data, cap: inline_cap(recording), inline_max: configuration.inline_upload_max_bytes)
    end

    def file_cap(recording)
      DirectUpload.max_file_size_for(recording)
    end

    def inline_cap(recording)
      file_max = file_cap(recording)
      configured = configuration.inline_upload_max_bytes
      file_max.blank? ? configured : [configured, file_max].min
    end

    def configuration
      RecordingStudioAttachable.configuration
    end
    private_class_method :ready!, :ticket_for, :authorize!, :denial, :remote_file, :parse_url, :chosen_filename,
                         :decoded, :file_cap, :inline_cap, :configuration
  end
end
