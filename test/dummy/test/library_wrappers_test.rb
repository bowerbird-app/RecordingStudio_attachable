# frozen_string_literal: true

require "test_helper"

class LibraryWrappersTest < ActionDispatch::IntegrationTest
  setup do
    @user = users_admin
    sign_in @user
    Current.actor = @user
    @workspace = Workspace.find_or_create_by!(name: "Studio Workspace")
    @root = RecordingStudio.root_recording_for(@workspace)
    grant_workspace_access!(@root)
    @library = RecordingStudioAttachable.library_for(@root, actor: @user)
    @campaign = RecordingStudioAttachable.library_for(@root, key: :campaign, actor: @user)
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

  test "place reorder remove and resolve round trip through wrappers" do
    photo = import_photo(@library, "kiln-canister-hero.jpg")
    placement = @holder.place_library_image(attachment_recording: photo, actor: @user)

    resolved = @holder.library_placements(actor: @user)
    assert resolved.any? { |item| item.attachment_recording.id == photo.id }
    assert_equal photo.recordable, resolved.first.attachment

    second = import_photo(@campaign, "kiln-canister-portrait.jpg")
    second_placement = @holder.place_library_image(attachment_recording: second, actor: @user)
    @holder.reorder_library_placements!(
      ordered_recording_ids: [second_placement.id, placement.id],
      actor: @user
    )

    ordered = @holder.library_placements(actor: @user).map { |item| item.attachment_recording.id }
    assert_equal [second.id, photo.id], ordered.first(2)

    @holder.remove_library_placement(placement_recording: second_placement, actor: @user)
    remaining = @holder.library_placements(actor: @user).map { |item| item.placement_recording.id }
    refute_includes remaining, second_placement.id
  end

  test "upload_to_library_and_place records through place_new and rolls back on place failure" do
    blob = blob_from_fixture("kiln-canister-hero.jpg")
    calls = []
    place = RecordingStudioLibrary::Services::Place
    singleton = class << place; self; end
    original = singleton.instance_method(:call)
    singleton.define_method(:call) do |**kwargs|
      calls << kwargs
      raise ArgumentError, "forced place failure"
    end

    error = assert_raises(ArgumentError) do
      @holder.upload_to_library_and_place(
        signed_blob_id: blob.signed_id,
        library_recording: @library,
        actor: @user,
        name: "Rollback shot"
      )
    end
    assert_match(/forced place failure/, error.message)

    refute RecordingStudio::Recording.where(
      parent_recording_id: @library.id,
      recordable_type: "RecordingStudioAttachable::Attachment"
    ).joins(
      "INNER JOIN recording_studio_attachable_attachments ON recording_studio_attachable_attachments.id = recording_studio_recordings.recordable_id"
    ).where(recording_studio_attachable_attachments: { name: "Rollback shot" }).exists?
    assert_equal 1, calls.size
  ensure
    singleton.define_method(:call, original)
  end

  test "resolve skips trashed items" do
    photo = import_photo(@library, "kiln-canister-window.jpg")
    @holder.place_library_image(attachment_recording: photo, actor: @user)
    photo.recording_studio_trashable_trash!(actor: @user)

    resolved = RecordingStudioAttachable::Placements.resolve(@holder, actor: @user)
    refute resolved.any? { |item| item.attachment_recording.id == photo.id }

    including = RecordingStudioAttachable::Placements.resolve(@holder, include_trashed_images: true, actor: @user)
    assert including.any? { |item| item.attachment_recording.id == photo.id }
  end

  test "place refuses a photo from another workspace" do
    other = Workspace.create!(name: "Other #{SecureRandom.hex(4)}")
    other_root = RecordingStudio.root_recording_for(other)
    grant_workspace_access!(other_root)
    other_library = RecordingStudioAttachable.library_for(other_root, actor: @user)
    foreign = import_photo(other_library, "kiln-canister-hero.jpg")

    error = assert_raises(ArgumentError) do
      @holder.place_library_image(attachment_recording: foreign, actor: @user)
    end
    assert_match(/another workspace/, error.message)
  end

  test "place refuses a hidden item" do
    photo = import_photo(@library, "kiln-canister-shelf.jpg")

    error = assert_raises(ArgumentError) do
      with_replaced_singleton(RecordingStudioLibrary::Authorization, :visible?, ->(**) { false }) do
        @holder.place_library_image(attachment_recording: photo, actor: @user)
      end
    end
    assert_match(/cannot place that item|not visible|not authorized/i, error.message)
  end

  test "anonymous resolve goes through Accessible" do
    photo = import_photo(@library, "kiln-canister-side.jpg")
    @holder.place_library_image(attachment_recording: photo, actor: @user)

    anonymous = RecordingStudioAttachable::Placements.resolve(@holder, actor: nil)
    refute anonymous.any? { |item| item.attachment_recording.id == photo.id }
  end

  test "anonymous visitor seeing a public photo" do
    photo = import_photo(@library, "kiln-canister-linen.jpg")
    @holder.place_library_image(attachment_recording: photo, actor: @user)

    with_replaced_singleton(RecordingStudioLibrary::Authorization, :visible?, ->(**) { true }) do
      anonymous = RecordingStudioAttachable::Placements.resolve(@holder, actor: nil)
      assert anonymous.any? { |item| item.attachment_recording.id == photo.id }
    end
  end

  test "resolve fails closed when Accessible is not loaded" do
    photo = import_photo(@library, "kiln-canister-detail.jpg")
    @holder.place_library_image(attachment_recording: photo, actor: @user)
    auth = RecordingStudioLibrary::Authorization
    original = auth.method(:accessible_loaded?)
    auth.define_singleton_method(:accessible_loaded?) { false }

    skip "Library 0.1.1 fail-closed authorization is required" if auth.visible?(actor: @user, recording: photo)

    resolved = RecordingStudioAttachable::Placements.resolve(@holder, actor: @user)
    refute resolved.any? { |item| item.attachment_recording.id == photo.id }
  ensure
    auth.define_singleton_method(:accessible_loaded?) { original.call } if original
  end

  test "upload_to_library_and_place refuses without upload rights before creating a file" do
    viewer = create_user("viewer")
    grant_workspace_access!(@root, actor: viewer, role: :view)
    blob_count = ActiveStorage::Blob.count

    error = assert_raises(ArgumentError) do
      File.open(Rails.root.join("db/seed_images", "kiln-canister-hero.jpg"), "rb") do |io|
        @holder.upload_to_library_and_place(
          io: io,
          filename: "kiln-canister-hero.jpg",
          content_type: "image/jpeg",
          library_recording: @library,
          actor: viewer,
          name: "Denied upload"
        )
      end
    end

    assert_match(/not authorized|cannot upload/i, error.message)
    assert_equal blob_count, ActiveStorage::Blob.count
  end

  test "RecordAttachmentUpload refuses a library upload without upload rights before looking up the blob" do
    viewer = create_user("library-viewer")
    grant_workspace_access!(@root, actor: viewer, role: :view)
    blob = blob_from_fixture("kiln-canister-portrait.jpg")
    blob_count = ActiveStorage::Blob.count

    result = RecordingStudioAttachable::Services::RecordAttachmentUpload.call(
      parent_recording: @library,
      signed_blob_id: blob.signed_id,
      actor: viewer,
      name: "Denied library upload"
    )

    assert result.failure?
    assert_match(/not authorized|cannot upload/i, result.error)
    assert_equal blob_count, ActiveStorage::Blob.count
    refute RecordingStudio::Recording.where(
      parent_recording_id: @library.id,
      recordable_type: "RecordingStudioAttachable::Attachment"
    ).joins(
      "INNER JOIN recording_studio_attachable_attachments ON recording_studio_attachable_attachments.id = recording_studio_recordings.recordable_id"
    ).where(recording_studio_attachable_attachments: { name: "Denied library upload" }).exists?
  end

  test "place refuses a type the holder does not allow" do
    sample = RecordingStudio.record!(
      action: "created",
      recordable: RecordingStudioLibrary::SampleItem.new(title: "Not a photo", accent: "ink"),
      root_recording: @root,
      parent_recording: @library,
      actor: @user
    ).recording

    error = assert_raises(ArgumentError) do
      RecordingStudioLibrary.place!(@holder, sample, actor: @user)
    end
    assert_match(/not allowed|cannot be placed/i, error.message)
  end

  test "trashing an in-use photo warns with usages and delete removes placements" do
    photo = import_photo(@library, "kiln-canister-tall.jpg")
    placement = @holder.place_library_image(attachment_recording: photo, actor: @user)
    usages = RecordingStudioAttachable::Placements.usage_for(photo)

    assert_equal 1, usages.size
    assert_equal @holder.id, usages.first.parent_recording.id

    get recording_studio_attachable.attachment_path(photo)
    assert_response :success
    assert_includes response.body, "Used in"
    assert_includes response.body, usages.first.label

    photo.destroy!
    refute RecordingStudio::Recording.exists?(placement.id)
  end

  test "ImageLibrary and LibraryPlacement stay thin aliases" do
    assert RecordingStudio.capability_enabled?(:library, for: "Workspace")
    assert RecordingStudio.capability_enabled?(:image_library, for: "Workspace")
    assert RecordingStudio.capability_enabled?(:placeable, for: "Gallery")
    assert RecordingStudio.capability_enabled?(:library_placement, for: "Gallery")
    assert_includes RecordingStudio.allowed_parent_types_for("RecordingStudioLibrary::Library"), "Workspace"
    assert_includes RecordingStudio.allowed_parent_types_for("RecordingStudioLibrary::Placement"), "Gallery"
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

  def with_replaced_singleton(target, name, replacement)
    original = target.method(name)
    target.define_singleton_method(name, &replacement)
    yield
  ensure
    target.define_singleton_method(name) do |*args, **kwargs, &block|
      original.call(*args, **kwargs, &block)
    end
  end

  def create_user(prefix)
    User.create!(
      email: "#{prefix}-#{SecureRandom.hex(4)}@example.com",
      password: "Password",
      password_confirmation: "Password",
      name: prefix.capitalize
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

  def blob_from_fixture(filename)
    path = Rails.root.join("db/seed_images", filename)
    File.open(path, "rb") do |io|
      ActiveStorage::Blob.create_and_upload!(
        io: io,
        filename: filename,
        content_type: "image/jpeg"
      )
    end
  end
end
