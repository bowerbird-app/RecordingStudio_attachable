# frozen_string_literal: true

class ImageLibrariesController < ApplicationController
  include UsesDefaultLayout

  def show
    workspace = Workspace.first
    root_recording = RecordingStudio::Recording.unscoped.find_by(recordable: workspace, parent_recording_id: nil)
    return redirect_to root_path, alert: "Seed the workspace to open the library." if root_recording.blank?

    redirect_to recording_studio_attachable.library_path(
      root_recording,
      redirect_mode: "return_to",
      return_to: root_path
    )
  end
end
