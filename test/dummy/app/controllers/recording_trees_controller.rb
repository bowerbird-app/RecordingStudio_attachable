class RecordingTreesController < ApplicationController
  def index
    recordings = RecordingStudio::Recording.unscoped.includes(:recordable).order(:created_at).to_a

    @recording_children = recordings.group_by(&:parent_recording_id)
    @root_recordings = @recording_children[nil] || []
  end
end
