class PagesController < ApplicationController
  before_action :set_page
  before_action :set_attachment_picker_paths

  def show; end

  def edit; end

  def update
    if @page.update(page_params)
      redirect_to edit_page_path(@page), notice: "Page updated."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  private

  def set_page
    @page = Page.find(params[:id])
  end

  def set_attachment_picker_paths
    @page_recording = RecordingStudio::Recording.unscoped.find_by(recordable: @page)
    return if @page_recording.blank?

    @page_attachment_picker_path = recording_studio_attachable.recording_attachment_picker_path(@page_recording)
    @page_attachment_create_path = recording_studio_attachable.recording_attachment_imports_path(
      @page_recording,
      redirect_mode: "return_to",
      return_to: page_path(@page)
    )
  end

  def page_params
    params.require(:page).permit(:title, :body)
  end
end
