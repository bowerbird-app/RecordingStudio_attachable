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
        model: RecordingStudioAttachable::Attachment,
        blast_radius: :site,
        scope: method(:live_current_attachments),
        api_authorize: ->(context) { RecordingStudioAttachable::Api::Access.can_view?(context) }
      ) do
        RecordingStudioAttachable::Metrics.define_metrics(self)
      end
    end

    def define_metrics(dsl)
      dsl.sum :storage_used, title: "Storage used", field: :byte_size, unit: "bytes", expose: EXPOSE
      dsl.timeseries :uploads_over_time, title: "Uploads over time", field: :created_at, expose: EXPOSE
      dsl.breakdown :by_kind, title: "Uploads by kind", field: :attachment_kind, expose: EXPOSE
      dsl.breakdown :by_content_type, title: "Uploads by content type", field: :content_type, expose: EXPOSE
    end

    def live_current_attachments(relation)
      recordings = RecordingStudio::Recording.where(
        recordable_type: RECORDABLE_TYPE,
        trashed_at: nil
      )
      relation.where(id: recordings.select(:recordable_id))
    end
  end
end
