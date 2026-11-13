# frozen_string_literal: true

require "test_helper"

class SiteSettingsBootTest < ActionDispatch::IntegrationTest
  setup do
    @user = User.find_by(email: "admin@admin.com")
    if @user.blank?
      @user = User.create!(
        email: "admin@admin.com",
        password: "Password",
        password_confirmation: "Password",
        name: "Avery"
      )
    end
    sign_in @user
    workspace = Workspace.find_or_create_by!(name: "Studio Workspace")
    Current.actor = @user
    @root = RecordingStudio.root_recording_for(workspace)
    grant_workspace_access!(@root)
  end

  teardown do
    Current.actor = nil if defined?(Current)
  end

  test "signed-in admin can open site settings screens" do
    get "/recording_studio_site_settings"
    assert_response :success

    get "/recording_studio_site_settings/settings"
    assert_response :success
  end

  test "signed-in admin can open attachable library and upload screens" do
    get recording_studio_attachable.recording_attachments_path(@root)
    assert_response :success

    get recording_studio_attachable.recording_attachment_upload_path(@root)
    assert_response :success
  end

  def grant_workspace_access!(root)
    original = RecordingStudioAccessible.configuration.access_management_authorizer
    RecordingStudioAccessible.configuration.access_management_authorizer = ->(**) { true }
    result = RecordingStudioAccessible.bootstrap_owner_access!(recording: root, actor: @user)
    raise result.error if result.failure?
  ensure
    RecordingStudioAccessible.configuration.access_management_authorizer = original
  end
end
