class UsersController < ApplicationController
  include UsesDefaultLayout

  def show
    @user = User.find(params[:id])
    root_recording = RecordingStudio.root_recording_for(Workspace.first!)
    @user_recording = RecordingStudio::Recording.unscoped.find_by!(
      recordable: @user,
      root_recording_id: root_recording.id
    )
    @return_to = user_path(@user)
  end
end
