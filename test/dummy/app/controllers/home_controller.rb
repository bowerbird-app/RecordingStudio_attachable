class HomeController < ApplicationController
  def index
    @workspace = Workspace.first
    @page = Page.first
    @chat_demo_path = chat_demo_path
    @page_show_path = page_path(@page) if @page.present?
    @page_edit_path = edit_page_path(@page) if @page.present?
    @root_recording = RecordingStudio::Recording.unscoped.find_by(
      recordable: @workspace,
      parent_recording_id: nil
    )
    @page_recording = RecordingStudio::Recording.unscoped.find_by(
      recordable: @page,
      root_recording_id: @root_recording&.id
    )

    @root_attachment_listing_path = attachment_listing_path(@root_recording, scope: :subtree, kind: :all)
    @root_attachment_upload_path = attachment_upload_path(@root_recording)
    @page_attachment_listing_path = attachment_listing_path(@page_recording)
    @page_attachment_upload_path = page_attachment_upload_path
  end

  private

  def attachment_listing_path(recording, scope: :direct, kind: :all)
    return if recording.blank?

    "/recording_studio_attachable/recordings/#{recording.id}/attachments?scope=#{scope}&kind=#{kind}"
  end

  def attachment_upload_path(recording)
    return if recording.blank?

    "/recording_studio_attachable/recordings/#{recording.id}/attachments/upload"
  end

  def page_attachment_upload_path
    return if @page_recording.blank? || @page.blank?

    recording_studio_attachable.recording_attachment_upload_path(
      @page_recording,
      redirect_mode: "return_to",
      return_to: @page_show_path
    )
  end
end
