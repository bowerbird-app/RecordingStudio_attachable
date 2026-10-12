# frozen_string_literal: true

class GalleriesController < ApplicationController
  include UsesDefaultLayout

  def show
    return unless load_gallery!

    redirect_to recording_studio_library.recording_placements_path(
      @gallery_recording,
      redirect_mode: "return_to",
      return_to: root_path
    )
  end

  def edit
    return unless load_gallery!

    @return_to = edit_gallery_path(@gallery)
  end

  private

  def load_gallery!
    @gallery = Gallery.find(params[:id])
    @gallery_recording = RecordingStudio::Recording.unscoped.find_by(recordable: @gallery)
    return true if @gallery_recording.present?

    redirect_to root_path, alert: "Seed the gallery to open this page."
    false
  end
end
