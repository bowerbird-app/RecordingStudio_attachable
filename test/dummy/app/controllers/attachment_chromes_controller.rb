class AttachmentChromesController < ApplicationController
  include UsesDefaultLayout

  def show
    @page = Page.first!
    root_recording = RecordingStudio.root_recording_for(Workspace.first!)
    @page_recording = RecordingStudio::Recording.unscoped.find_by!(
      recordable: @page,
      root_recording_id: root_recording.id
    )
    @return_to = attachment_chromes_path
  end
end
