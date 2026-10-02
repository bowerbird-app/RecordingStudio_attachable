# frozen_string_literal: true

class AttachmentEditorsController < ApplicationController
  def show
    @recording = RecordingStudio.root_recording_for(Workspace.first!)
    @return_to = attachment_editor_path
  end
end
