# frozen_string_literal: true

module RecordingStudioAttachable
  module Services
    class ImportRemoteFiles < ApplicationService
      def initialize(parent_recording:, payloads:, provider_key:, actor: nil, impersonator: nil)
        @parent_recording = parent_recording
        @payloads = Array(payloads)
        @provider_key = provider_key.to_s
        @actor = actor
        @impersonator = impersonator
      end

      private

      attr_reader :parent_recording, :payloads, :provider_key, :actor, :impersonator

      def perform
        downloaded = []
        attachments = payloads.map { |payload| materialize(payload, downloaded) }
        ImportAttachments.call(
          parent_recording: parent_recording,
          attachments: attachments,
          actor: actor,
          impersonator: impersonator,
          source: provider_key
        )
      ensure
        downloaded&.each { |io| RecordingStudioAttachable::SafeRemoteFetch.close_io(io) }
      end

      def materialize(payload, downloaded)
        reject_oversized!(payload[:byte_size])
        fetched = download(payload)
        io = fetched.fetch(:io)
        downloaded << io
        reject_oversized!(fetched[:byte_size] || io_size(io))
        {
          io: io,
          filename: fetched[:filename].presence || payload[:filename],
          content_type: fetched[:content_type].presence || payload[:content_type],
          name: payload[:name].presence || fetched[:filename].presence || payload[:filename],
          description: payload[:description],
          metadata: stamped_metadata(payload)
        }
      end

      def download(payload)
        source = payload[:download]
        if source.respond_to?(:call)
          normalize_download(source.call, payload)
        elsif payload[:io]
          { io: payload[:io], filename: payload[:filename], content_type: payload[:content_type] }
        else
          raise ArgumentError, "Remote import payload must include download or io"
        end
      end

      def normalize_download(result, payload)
        if result.respond_to?(:to_h) && result.to_h.key?(:io)
          hash = result.to_h.symbolize_keys
          {
            io: hash.fetch(:io),
            filename: hash[:filename].presence || payload[:filename],
            content_type: hash[:content_type].presence || payload[:content_type],
            byte_size: hash[:byte_size]
          }
        elsif result.respond_to?(:read) || result.respond_to?(:binmode)
          { io: result, filename: payload[:filename], content_type: payload[:content_type] }
        else
          raise ArgumentError, "download must return io: or an IO"
        end
      end

      def stamped_metadata(payload)
        metadata = payload.fetch(:metadata, {}).to_h.symbolize_keys
        {
          provider: provider_key,
          external_id: metadata[:external_id],
          external_url: metadata[:external_url]
        }.compact.merge(metadata.except(:provider, :external_id, :external_url))
      end

      def reject_oversized!(byte_size)
        max_bytes = RecordingStudioAttachable.configuration.max_file_size
        return if max_bytes.blank? || byte_size.blank?

        raise ArgumentError, "Remote file exceeds maximum file size" if byte_size.to_i > max_bytes
      end

      def io_size(io)
        return io.size if io.respond_to?(:size)

        nil
      end
    end
  end
end
