# frozen_string_literal: true

require_relative "api/access"
require "recording_studio_metrics"

module RecordingStudioAttachable
  module Metrics
    RESOURCE = :attachments
    API = :operations
    RECORDABLE_TYPE = "RecordingStudioAttachable::Attachment"
    EXPOSE = { api: [API] }.freeze

    module_function

    def register!
      RecordingStudioMetrics.register(
        RESOURCE,
        model: RecordingStudio::Recording,
        blast_radius: :site,
        scope: method(:live_attachment_recordings),
        api_authorize: ->(context) { RecordingStudioAttachable::Api::Access.can_view?(context) }
      ) do
        RecordingStudioAttachable::Metrics.define_metrics(self)
      end
    end

    def define_metrics(dsl)
      dsl.custom :storage_used, result_type: :scalar, title: "Storage used", unit: "bytes", expose: EXPOSE,
                 &storage_used_calculator
      dsl.timeseries :uploads_over_time, title: "Uploads over time", field: :created_at, expose: EXPOSE
      dsl.custom :by_kind, result_type: :breakdown, title: "Uploads by kind", expose: EXPOSE, &breakdown_calculator(:attachment_kind)
      dsl.custom :by_content_type, result_type: :breakdown, title: "Uploads by content type", expose: EXPOSE,
                 &breakdown_calculator(:content_type)
    end

    def live_attachment_recordings(relation)
      relation.where(recordable_type: RECORDABLE_TYPE, trashed_at: nil)
    end

    def storage_used_calculator
      lambda do |relation, _context|
        join_current_attachments(relation).sum(attachment_table[:byte_size])
      end
    end

    def breakdown_calculator(field)
      lambda do |relation, _context|
        join_current_attachments(relation).group(attachment_table[field]).count.map do |key, value|
          { key: key, value: value }
        end
      end
    end

    def join_current_attachments(relation)
      recordings = relation.arel_table
      attachments = attachment_table
      relation.joins(
        recordings.join(attachments).on(attachments[:id].eq(recordings[:recordable_id])).join_sources
      )
    end

    def attachment_table
      RecordingStudioAttachable::Attachment.arel_table
    end
  end
end
