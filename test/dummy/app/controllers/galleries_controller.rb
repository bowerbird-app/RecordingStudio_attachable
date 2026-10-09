# frozen_string_literal: true

class GalleriesController < ApplicationController
  include UsesDefaultLayout

  def show
    @gallery = Gallery.find(params[:id])
    @gallery_recording = RecordingStudio::Recording.unscoped.find_by(recordable: @gallery)
    return redirect_to root_path, alert: "Seed the gallery to open this page." if @gallery_recording.blank?

    redirect_to recording_studio_attachable.recording_placements_path(
      @gallery_recording,
      redirect_mode: "return_to",
      return_to: root_path
    )
  end
end
