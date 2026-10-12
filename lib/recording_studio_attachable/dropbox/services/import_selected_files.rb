# frozen_string_literal: true

require_relative "../../../../app/services/recording_studio_attachable/services/application_service"

module RecordingStudioAttachable
  module Dropbox
    module Services
      # rubocop:disable Metrics/ParameterLists, Metrics/AbcSize, Metrics/MethodLength
      class ImportSelectedFiles < RecordingStudioAttachable::Services::ApplicationService
        def initialize(parent_recording:, file_ids:, access_token:, actor: nil, impersonator: nil, client: nil)
          super()
          @parent_recording = parent_recording
          @file_ids = file_ids
          @access_token = access_token
          @actor = actor
          @impersonator = impersonator
          @client = client
        end

        private

        attr_reader :parent_recording, :file_ids, :access_token, :actor, :impersonator, :client

        def perform
          selections = normalized_file_selections
          raise ArgumentError, "Select at least one Dropbox file to import" if selections.blank?

          downloaded = []
          attachments = selections.map do |selection|
            remote_file = dropbox_client.resolve(selection)
            fetched = RecordingStudioAttachable::SafeRemoteFetch.call(
              remote_file,
              max_bytes: RecordingStudioAttachable.configuration.max_file_size
            )
            downloaded << fetched.io

            {
              io: fetched.io,
              filename: remote_file.filename,
              content_type: fetched.content_type || remote_file.content_type,
              name: remote_file.name,
              description: remote_file.description.presence || "Imported from Dropbox",
              metadata: {
                provider: "dropbox",
                external_id: remote_file.external_id
              }.compact.merge(selection.fetch("metadata", {}))
            }
          end

          RecordingStudioAttachable::Services::ImportAttachments.call(
            parent_recording: parent_recording,
            attachments: attachments,
            actor: actor,
            impersonator: impersonator,
            source: "dropbox"
          )
        ensure
          downloaded&.each { |io| RecordingStudioAttachable::SafeRemoteFetch.close_io(io) }
        end

        def normalized_file_selections
          Array(file_ids).filter_map do |selection|
            case selection
            when String
              selection.presence && { "id" => selection }
            when Hash
              normalized_selection_hash(selection)
            end
          end.uniq
        end

        def normalized_selection_hash(selection)
          id = selection_value(selection, :id)
          return if id.blank?

          {
            "id" => id.to_s,
            "name" => selection_value(selection, :name).to_s.presence,
            "description" => selection_value(selection, :description).to_s.presence,
            "metadata" => normalized_metadata(selection)
          }.compact
        end

        def selection_value(selection, *keys)
          keys.lazy.map { |key| selection[key.to_s] || selection[key] }.find(&:present?)
        end

        def normalized_metadata(selection)
          metadata = selection_value(selection, :metadata)
          metadata.respond_to?(:to_h) ? metadata.to_h.compact_blank : {}
        end

        def dropbox_client
          @dropbox_client ||= client || RecordingStudioAttachable::Dropbox::Client.new(access_token: access_token)
        end
      end
      # rubocop:enable Metrics/ParameterLists, Metrics/AbcSize, Metrics/MethodLength
    end
  end
end
