# frozen_string_literal: true

module RecordingStudioAttachable
  class RecordingAttachmentsController < ApplicationController
    def index
      @recording = find_recording
      authorize_attachment_action!(:view, @recording, capability_options: capability_options_for(@recording))
      @scope = params[:scope].presence&.to_sym || RecordingStudioAttachable.configuration.default_listing_scope
      @kind = params[:kind].presence&.to_sym || RecordingStudioAttachable.configuration.default_kind_filter
      @include_trashed = ActiveModel::Type::Boolean.new.cast(params[:include_trashed])
      @attachments = RecordingStudioAttachable::Queries::ForRecording.new(
        recording: @recording,
        scope: @scope,
        kind: @kind,
        include_trashed: @include_trashed
      ).call
      @can_upload = RecordingStudioAttachable::Authorization.allowed?(
        action: :upload,
        actor: current_attachable_actor,
        recording: @recording,
        capability_options: capability_options_for(@recording)
      )
    end

    private

    def capability_options_for(recording)
      RecordingStudio.capability_options(:attachable, for_type: recording.recordable_type) || {}
    end
  end
end
