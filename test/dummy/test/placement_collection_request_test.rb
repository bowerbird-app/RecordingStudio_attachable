# frozen_string_literal: true

require "test_helper"

class PlacementCollectionRequestTest < ActionDispatch::IntegrationTest
  setup do
    @user = users_admin
    sign_in @user
    Current.actor = @user
    @workspace = Workspace.find_or_create_by!(name: "Studio Workspace")
    @root = RecordingStudio.root_recording_for(@workspace)
    grant_workspace_access!(@root)
    @library = RecordingStudioAttachable.library_for(@root, actor: @user)
    @gallery = Gallery.find_or_create_by!(title: "Kiln shots")
    @holder = RecordingStudio::Recording.unscoped.find_or_create_by!(
      root_recording_id: @root.id,
      parent_recording_id: @root.id,
      recordable: @gallery
    )
  end

  teardown do
    Current.actor = nil
  end

  test "gallery images editor saves caption credit alt and reorder through Library" do
    first = import_photo(@library, "kiln-canister-hero.jpg")
    second = import_photo(@library, "kiln-canister-portrait.jpg")
    left = @holder.place_library_image(attachment_recording: first, actor: @user)
    right = @holder.place_library_image(attachment_recording: second, actor: @user)

    get edit_gallery_path(@gallery)
    assert_response :success
    assert_includes response.body, "Gallery images"
    assert_includes response.body, "Caption"
    assert_includes response.body, "Credit"
    assert_includes response.body, "Alt text"
    assert_includes response.body, recording_studio_library.recording_placements_path(@holder)
    assert_includes response.body, "name=\"items[#{left.id}][caption]\""
    assert_includes response.body, "name=\"ordered_recording_ids[]\""
    refute_includes response.body, "action=\"#{recording_studio_attachable.recording_placements_path(@holder)}\""

    patch recording_studio_library.recording_placements_path(@holder), params: {
      redirect_mode: "return_to",
      return_to: edit_gallery_path(@gallery),
      items: {
        left.id => { caption: "Hero shot", credit: "Ada", alt_text: "Kiln canister hero" },
        right.id => { caption: "Portrait on the wall", credit: "Bea", alt_text: "Kiln canister portrait" }
      },
      ordered_recording_ids: [right.id, left.id]
    }

    assert_response :redirect
    follow_redirect!
    assert_response :success

    first.reload
    second.reload
    assert_equal "Hero shot", first.recordable.caption
    assert_equal "Ada", first.recordable.credit
    assert_equal "Kiln canister hero", first.recordable.alt_text
    assert_equal "Portrait on the wall", second.recordable.caption
    assert_equal "Bea", second.recordable.credit
    assert_equal "Kiln canister portrait", second.recordable.alt_text

    ordered = @holder.library_placements(actor: @user).map { |item| item.attachment_recording.id }
    assert_equal [second.id, first.id], ordered.first(2)
  end

  test "gallery images editor JSON save returns ok through Library" do
    photo = import_photo(@library, "kiln-canister-hero.jpg")
    placement = @holder.place_library_image(attachment_recording: photo, actor: @user)

    patch recording_studio_library.recording_placements_path(@holder),
          params: {
            items: {
              placement.id => { caption: "Hero xhr", credit: "Ada", alt_text: "Kiln canister hero" }
            }
          },
          as: :json,
          headers: { "X-Requested-With" => "XMLHttpRequest" }

    assert_response :success
    assert_equal true, response.parsed_body["ok"]
    photo.reload
    assert_equal "Hero xhr", photo.recordable.caption
    assert_equal "Ada", photo.recordable.credit
    assert_equal "Kiln canister hero", photo.recordable.alt_text
  end

  private

  def users_admin
    user = User.find_by(email: "admin@admin.com")
    return user if user.present?

    User.create!(
      email: "admin@admin.com",
      password: "Password",
      password_confirmation: "Password",
      name: "Avery"
    )
  end

  def grant_workspace_access!(root, actor: @user, role: :admin)
    original = RecordingStudioAccessible.configuration.access_management_authorizer
    RecordingStudioAccessible.configuration.access_management_authorizer = ->(**) { true }
    result = RecordingStudioAccessible.grant_access(
      recording: root,
      actor: actor,
      role: role,
      manager_actor: @user
    )
    raise result.error if result.failure?
  ensure
    RecordingStudioAccessible.configuration.access_management_authorizer = original
  end

  def import_photo(library, filename)
    existing = library.images(per_page: 50).find { |recording| recording.recordable.original_filename == filename }
    return existing if existing.present?

    File.open(Rails.root.join("db/seed_images", filename), "rb") do |io|
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
end
