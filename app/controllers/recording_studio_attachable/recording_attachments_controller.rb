# frozen_string_literal: true

module RecordingStudioAttachable
  class RecordingAttachmentsController < ApplicationController
    def index
      @recording = find_recording
      capability_options = capability_options_for(@recording)

      authorize_attachment_action!(:view, @recording, capability_options: capability_options)
      @scope = RecordingStudioAttachable::Queries::ForRecording.normalize_scope(params[:scope])
      @kind = RecordingStudioAttachable::Queries::ForRecording.normalize_kind(params[:kind])
      @view_mode = resolve_view_mode(params[:view])
      @query = RecordingStudioAttachable::Queries::ForRecording.normalize_search(params[:q])
      @include_trashed = ActiveModel::Type::Boolean.new.cast(params[:include_trashed])
      @append_only = ActiveModel::Type::Boolean.new.cast(params[:append_only])
      attachment_query = RecordingStudioAttachable::Queries::ForRecording.new(
        recording: @recording,
        scope: @scope,
        kind: @kind,
        include_trashed: @include_trashed,
        search: @query,
        page: params[:page]
      )
      @attachments = attachment_query.call
      @page = attachment_query.current_page
      @total_count = attachment_query.total_count
      @total_pages = attachment_query.total_pages
      @can_upload = RecordingStudioAttachable::Authorization.allowed?(
        action: :upload,
        actor: current_attachable_actor,
        recording: @recording,
        capability_options: capability_options
      )
    end

    private

    def resolve_view_mode(requested_view)
      return requested_view.to_sym if requested_view.to_s.in?(%w[grid list])

      @kind.to_sym == :files ? :list : :grid
    end

    def recording_studio_resolved_layout
      return false if action_name == "index" && @append_only

      super
    end
  end
end
