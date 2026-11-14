# frozen_string_literal: true

require "test_helper"

class AttachmentImagePickerTest < ActionDispatch::IntegrationTest
  setup do
    @user = User.find_by(email: "admin@admin.com") || User.create!(
      email: "admin@admin.com",
      password: "Password",
      password_confirmation: "Password",
      name: "Avery"
    )
    sign_in @user
    workspace = Workspace.find_or_create_by!(name: "Studio Workspace")
    Current.actor = @user
    @root = RecordingStudio.root_recording_for(workspace)
    grant_workspace_access!(@root)
    @page = Page.create!(title: "Picker page #{SecureRandom.hex(4)}")
    @page_recording = RecordingStudio::Recording.unscoped.find_or_create_by!(
      root_recording_id: @root.id,
      parent_recording_id: @root.id,
      recordable: @page
    )
  end

  teardown do
    Current.actor = nil if defined?(Current)
  end

  test "editor modal renders the flatpack picker empty slot and toolbar" do
    get edit_page_path(@page)

    assert_response :success
    assert_includes response.body, 'data-flat-pack-picker-empty-slot="true"'
    assert_includes response.body, "No images found for this page yet."
    assert_includes response.body, 'data-flat-pack--picker-search-mode-value="remote"'
    assert_includes response.body, 'data-flat-pack--picker-modal-value="false"'
    assert_includes response.body, 'data-flat-pack-picker-variant="flush"'
    assert_includes response.body, "data-flat-pack-picker-toolbar"
    assert_includes response.body, "Upload"
    assert_includes response.body, recording_studio_attachable.recording_attachment_picker_path(@page_recording)
  end

  test "chat demo keeps the selected event and the picker empty state" do
    ChatThread.find_or_create_by!(title: "Workspace conversation")

    get chat_demo_path

    assert_response :success
    assert_includes response.body, "recording-studio-attachable--attachment-image-picker:selected->chat-demo#attachmentSelected"
    assert_includes response.body, 'data-flat-pack-picker-empty-slot="true"'
    assert_includes response.body, "No images are available in the workspace library yet."
  end

  test "picker pages append by returning the next page number and the attachment payload" do
    first = attach("first-picker.png")
    second = attach("second-picker.png")

    page_one = picker_json(page: 1)
    page_two = picker_json(page: 2)

    assert_equal 1, page_one.fetch("items").length
    assert_equal 2, page_one.dig("pagination", "next_page")
    assert_equal 1, page_two.fetch("items").length
    assert_nil page_two.dig("pagination", "next_page")
    assert_equal 2, page_two.dig("pagination", "current_page")

    ids = [ page_one, page_two ].map { |page| page.fetch("items").first.fetch("id").to_s }
    assert_equal [ second.id, first.id ].map(&:to_s).sort, ids.sort
    assert_equal 2, ids.uniq.size

    [ page_one, page_two ].each do |page|
      item = page.fetch("items").first
      assert_equal "image", item.fetch("kind")
      assert_equal item.fetch("id").to_s, item.dig("payload", "id").to_s
      assert_equal item.fetch("name"), item.dig("payload", "name")
      assert item.dig("payload", "insert_url").present?
      assert item.dig("payload", "thumbnail_url").present?
    end
  end

  test "an empty library returns no items and no next page" do
    payload = picker_json(page: 1)

    assert_equal [], payload.fetch("items")
    assert_nil payload.dig("pagination", "next_page")
  end

  private

  def picker_json(page:)
    get recording_studio_attachable.recording_attachment_picker_path(@page_recording),
        params: { page: page, per_page: 1 },
        as: :json

    assert_response :success
    JSON.parse(response.body)
  end

  def attach(filename)
    blob = ActiveStorage::Blob.create_and_upload!(
      io: StringIO.new(png_bytes),
      filename: filename,
      content_type: "image/png"
    )
    attachment = RecordingStudioAttachable::Attachment.build_from_blob(
      blob: blob,
      name: filename,
      root_recording: @root
    )
    RecordingStudio.record!(
      action: "attachment_uploaded",
      recordable: attachment,
      root_recording: @root,
      parent_recording: @page_recording,
      actor: @user
    ).recording
  end

  def png_bytes
    Base64.decode64("iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==")
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
