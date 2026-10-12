# frozen_string_literal: true

require_relative "../../../app/services/recording_studio_attachable/services/application_service"

module RecordingStudioAttachable
  module Adapter
    class ImportSelectedFiles < RecordingStudioAttachable::Services::ApplicationService
      def initialize(parent_recording:, file_ids:, access_token:, **options)
        super()
        @parent_recording = parent_recording
        @file_ids = file_ids
        @access_token = access_token
        @actor = options[:actor]
        @impersonator = options[:impersonator]
        @client = options[:client]
      end

      private

      attr_reader :parent_recording, :file_ids, :access_token, :actor, :impersonator, :client

      def perform
        selections = Adapter::Selection.files(file_ids, extra_keys: extra_selection_keys)
        raise ArgumentError, blank_selection_message if selections.blank?

        downloaded = []
        attachments = selections.map { |selection| download_attachment(selection, downloaded) }
        import_attachments(attachments)
      ensure
        downloaded&.each { |io| RecordingStudioAttachable::SafeRemoteFetch.close_io(io) }
      end

      def download_attachment(selection, downloaded)
        remote_file = adapter_client.resolve(selection)
        fetched = RecordingStudioAttachable::SafeRemoteFetch.call(
          remote_file,
          max_bytes: RecordingStudioAttachable.configuration.max_file_size
        )
        downloaded << fetched.io
        attachment_payload(remote_file, fetched, selection)
      end

      def import_attachments(attachments)
        RecordingStudioAttachable::Services::ImportAttachments.call(
          parent_recording: parent_recording,
          attachments: attachments,
          actor: actor,
          impersonator: impersonator,
          source: provider_key
        )
      end

      def attachment_payload(remote_file, fetched, selection)
        {
          io: fetched.io,
          filename: remote_file.filename,
          content_type: fetched.content_type || remote_file.content_type,
          name: remote_file.name.presence || remote_file.filename,
          description: selection["description"].presence || remote_file.description.presence || default_description,
          metadata: attachment_metadata(remote_file, selection)
        }
      end

      def attachment_metadata(remote_file, selection)
        {
          provider: provider_key,
          external_id: remote_file.external_id,
          external_url: remote_file.external_url
        }.compact.merge(selection.fetch("metadata", {}))
      end

      def adapter_client
        @adapter_client ||= client || build_client
      end

      def extra_selection_keys
        {}
      end
    end
  end
end
