# frozen_string_literal: true

module RecordingStudioAttachable
  class RecordingAttachmentsController < ApplicationController
    def index
      @recording = find_recording
      capability_options = capability_options_for(@recording)

      authorize_attachment_action!(:view, @recording, capability_options: capability_options)
      @scope = RecordingStudioAttachable::Queries::ForRecording.normalize_scope(params[:scope])
      @kind = RecordingStudioAttachable::Queries::ForRecording.normalize_kind(params[:kind])
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
        capability_options: capability_options
      )
    end
  end
end
