# frozen_string_literal: true

require "test_helper"

class ImageLibraryTest < ActionDispatch::IntegrationTest
  setup do
    @user = User.find_or_initialize_by(email: "admin@admin.com")
    @user.password = "Password"
    @user.password_confirmation = "Password"
    @user.name = "Avery" if @user.name.blank?
    @user.save!
    sign_in @user
  end

  test "image library path creates the library and lists photos" do
    workspace = Workspace.find_or_create_by!(name: "Studio Workspace")
    Current.actor = @user
    root = RecordingStudio.root_recording_for(workspace)
    grant_workspace_access!(root)

    get image_library_path
    assert_response :redirect
    follow_redirect!
    assert_response :redirect
    follow_redirect!

    library = RecordingStudioAttachable.library_for(root, actor: @user)
    assert_equal library.id.to_s, path.split("/")[3]
    assert_includes response.body, "Library"
  end

  test "gallery show opens placements for the seeded gallery" do
    workspace = Workspace.find_or_create_by!(name: "Studio Workspace")
    Current.actor = @user
    root = RecordingStudio.root_recording_for(workspace)
    grant_workspace_access!(root)
    gallery = Gallery.find_or_create_by!(title: "Kiln shots")
    gallery_recording = RecordingStudio::Recording.unscoped.find_or_create_by!(
      root_recording_id: root.id,
      parent_recording_id: root.id,
      recordable: gallery
    )

    get gallery_path(gallery)
    assert_response :redirect
    follow_redirect!

    assert_includes path, "/placements"
    assert_includes response.body, "Images"
    assert_equal gallery_recording.id.to_s, path.split("/")[3]
  end

  test "workspace enables the image library and gallery holds placements" do
    assert RecordingStudio.capability_enabled?(:image_library, for: "Workspace")
    assert RecordingStudio.capability_enabled?(:library_placement, for: "Gallery")
    assert_includes RecordingStudio.allowed_parent_types_for("RecordingStudioAttachable::Library"), "Workspace"
    assert_includes RecordingStudio.allowed_parent_types_for("RecordingStudioAttachable::Placement"), "Gallery"
  end

  private

  def grant_workspace_access!(root)
    original = RecordingStudioAccessible.configuration.access_management_authorizer
    RecordingStudioAccessible.configuration.access_management_authorizer = ->(**) { true }
    result = RecordingStudioAccessible.grant_access(
      recording: root,
      actor: @user,
      role: :admin,
      manager_actor: @user
    )
    raise result.error if result.failure?
  ensure
    RecordingStudioAccessible.configuration.access_management_authorizer = original
  end
end
