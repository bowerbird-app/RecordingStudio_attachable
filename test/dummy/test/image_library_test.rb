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

  test "host images path opens the default keyed library listing" do
    workspace = Workspace.find_or_create_by!(name: "Studio Workspace")
    Current.actor = @user
    root = RecordingStudio.root_recording_for(workspace)
    grant_workspace_access!(root)
    library = RecordingStudioAttachable.library_for(root, actor: @user)

    get workspace_images_path
    assert_response :redirect
    follow_redirect!
    assert_includes path, "/recordings/#{root.id}/library"
    follow_redirect!
    assert_includes path, "/recordings/#{library.id}/attachments"
    assert_includes response.body, "Library"
  end

  test "host campaign path opens the campaign keyed library listing" do
    workspace = Workspace.find_or_create_by!(name: "Studio Workspace")
    Current.actor = @user
    root = RecordingStudio.root_recording_for(workspace)
    grant_workspace_access!(root)
    library = RecordingStudioAttachable.library_for(root, key: :campaign, actor: @user)

    get campaign_images_path
    assert_response :redirect
    follow_redirect!
    assert_includes path, "/recordings/#{root.id}/library"
    assert_includes request.fullpath, "key=campaign"
    follow_redirect!
    assert_includes path, "/recordings/#{library.id}/attachments"
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
    assert_includes response.body, "Add from library"
    assert_includes response.body, "Upload"
    assert_equal gallery_recording.id.to_s, path.split("/")[3]
  end

  test "gallery placements reuse list slides and grid" do
    workspace = Workspace.find_or_create_by!(name: "Studio Workspace")
    Current.actor = @user
    root = RecordingStudio.root_recording_for(workspace)
    grant_workspace_access!(root)
    images = RecordingStudioAttachable.library_for(root, actor: @user)
    gallery = Gallery.find_or_create_by!(title: "Kiln shots")
    gallery_recording = RecordingStudio::Recording.unscoped.find_or_create_by!(
      root_recording_id: root.id,
      parent_recording_id: root.id,
      recordable: gallery
    )
    photo = first_or_import_photo(images, "kiln-canister-hero.jpg")
    clear_placements(gallery_recording)
    gallery_recording.place_library_image(attachment_recording: photo, actor: @user)

    get gallery_path(gallery)
    follow_redirect!

    assert_includes response.body, "List"
    assert_includes response.body, "Slides"
    assert_includes response.body, "Grid"
    assert_includes response.body, "Add from library"
    assert_includes response.body, "Upload"
    assert_includes response.body, "Remove from here"
    assert_includes response.body, "attachment_collection[rows][][caption]"
    assert_includes response.body, "flat-pack-input"
    assert_includes response.body, "border-[var(--surface-border-color)]"
    assert_includes response.body, "grid-cols-1"
    assert_includes response.body, "sm:grid-cols-2"
    assert_includes response.body, "Edit #{photo.recordable.name}"
    assert_not_includes response.body, ">Order<"
    assert_not_includes response.body, ">Drag<"
    assert_not_includes response.body, "Move up"
    assert_not_includes response.body, "Move down"
  end

  test "gallery places photos from two host-mounted libraries" do
    workspace = Workspace.find_or_create_by!(name: "Studio Workspace")
    Current.actor = @user
    root = RecordingStudio.root_recording_for(workspace)
    grant_workspace_access!(root)
    images = RecordingStudioAttachable.library_for(root, actor: @user)
    campaign = RecordingStudioAttachable.library_for(root, key: :campaign, actor: @user)
    gallery = Gallery.find_or_create_by!(title: "Kiln shots")
    gallery_recording = RecordingStudio::Recording.unscoped.find_or_create_by!(
      root_recording_id: root.id,
      parent_recording_id: root.id,
      recordable: gallery
    )

    images_photo = first_or_import_photo(images, "kiln-canister-hero.jpg")
    campaign_photo = first_or_import_photo(campaign, "kiln-canister-portrait.jpg")
    clear_placements(gallery_recording)
    gallery_recording.place_library_image(attachment_recording: images_photo, actor: @user)
    gallery_recording.place_library_image(attachment_recording: campaign_photo, actor: @user)

    placed_library_ids = gallery_recording.library_placements.map { |item| item.attachment_recording.parent_recording_id }
    assert_equal 2, placed_library_ids.size
    assert_includes placed_library_ids, images.id
    assert_includes placed_library_ids, campaign.id
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

  def first_or_import_photo(library, filename)
    existing = library.images(per_page: 20).find { |recording| recording.recordable.original_filename == filename }
    return existing if existing.present?

    path = Rails.root.join("db/seed_images", filename)
    File.open(path, "rb") do |io|
      library.import_attachment(
        io: io,
        filename: filename,
        content_type: "image/jpeg",
        name: filename,
        actor: @user,
        source: "test"
      )
    end
  end

  def clear_placements(gallery_recording)
    gallery_recording.library_placements.each do |item|
      gallery_recording.remove_library_placement(placement_recording: item.placement_recording, actor: @user)
    end
  end
end
