class HomeController < ApplicationController
  def index
    @workspace = Workspace.first
    @root_recording = RecordingStudio::Recording.unscoped.find_by(
      recordable: @workspace,
      parent_recording_id: nil
    )
    @attachment_listing_path = "/recording_studio_attachable/recordings/#{@root_recording.id}/attachments" if @root_recording.present?
    @attachment_upload_path = "/recording_studio_attachable/recordings/#{@root_recording.id}/attachments/upload" if @root_recording.present?
  end
end
