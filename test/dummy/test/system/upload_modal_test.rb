# frozen_string_literal: true

require "application_system_test_case"

class UploadModalSystemTest < ApplicationSystemTestCase
  # The browser runs in another thread and cannot see an open transaction.
  self.use_transactional_tests = false

  setup do
    @user = User.find_by(email: "admin@admin.com") || User.create!(
      email: "admin@admin.com", password: "Password", password_confirmation: "Password", name: "Avery"
    )
    @workspace = Workspace.find_or_create_by!(name: "Studio Workspace")
    Current.actor = @user
    @root = RecordingStudio.root_recording_for(@workspace)
    grant_workspace_access!(@root)
    login_as @user, scope: :user
  end

  test "Add files opens the uploader in a modal, uploads, closes, and refreshes the editor" do
    visit attachment_editor_path
    modal_id = "attachable-upload-modal-#{@root.id}"
    first_name = "upload-modal-#{SecureRandom.hex(4)}.png"
    second_name = "upload-modal-#{SecureRandom.hex(4)}.png"

    assert_no_selector "##{modal_id}", visible: true
    click_on "Add files"

    within "##{modal_id}" do
      assert_text "Drag and drop, or choose", wait: 10
      assert_no_text "Back"
      drop_disallowed_file
      assert_text "notes.txt"
      assert_text "not allowed"
      attach_file [png_file(first_name), png_file(second_name)], make_visible: true
    end

    assert_no_selector "##{modal_id}", visible: true, wait: 20
    assert_current_path attachment_editor_path
    # The list shows each image. Caption fields do not include the file name, so the refreshed row is the visible alt.
    assert_selector "turbo-frame#attachment-editor-images img[alt='#{File.basename(first_name, ".*")}']", wait: 10
    assert_selector "turbo-frame#attachment-editor-images img[alt='#{File.basename(second_name, ".*")}']"
  end

  test "the standard upload page still redirects after upload" do
    filename = "upload-page-#{SecureRandom.hex(4)}.png"
    visit recording_studio_attachable.recording_attachment_upload_path(
      @root, redirect_mode: "return_to", return_to: attachment_editor_path
    )

    attach_file png_file(filename), make_visible: true

    assert_current_path attachment_editor_path, wait: 20
    assert_selector "img[alt='#{File.basename(filename, ".*")}']"
  end

  private

  def drop_disallowed_file
    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 10
    until uploader_connected?
      raise "uploader did not connect" if Process.clock_gettime(Process::CLOCK_MONOTONIC) > deadline

      sleep 0.05
    end

    # text/plain is an allowed workspace type, so the drop uses a type the library rejects.
    page.execute_script(<<~JS)
      const zone = document.querySelector("[data-recording-studio-attachable--upload-target='dropzone']")
      const file = new File(["hello"], "notes.txt", { type: "application/zip" })
      const dataTransfer = new DataTransfer()
      dataTransfer.items.add(file)
      zone.dispatchEvent(new DragEvent("drop", { bubbles: true, cancelable: true, dataTransfer }))
    JS
  end

  def uploader_connected?
    page.evaluate_script(<<~JS)
      (() => {
        const zone = document.querySelector("[data-recording-studio-attachable--upload-target='dropzone']")
        const root = zone && zone.closest("[data-controller~='recording-studio-attachable--upload']")
        const stimulus = window.Stimulus
        return Boolean(stimulus && root && stimulus.getControllerForElementAndIdentifier(root, "recording-studio-attachable--upload"))
      })()
    JS
  end

  def png_file(name)
    path = Rails.root.join("tmp", name)
    FileUtils.mkdir_p(path.dirname)
    File.binwrite(path, Base64.decode64(TINY_PNG))
    path.to_s
  end

  def grant_workspace_access!(root)
    original = RecordingStudioAccessible.configuration.access_management_authorizer
    RecordingStudioAccessible.configuration.access_management_authorizer = ->(**) { true }
    result = RecordingStudioAccessible.grant_access(
      recording: root, actor: @user, role: :admin, manager_actor: @user
    )
    raise result.error if result.failure?
  ensure
    RecordingStudioAccessible.configuration.access_management_authorizer = original
  end

  TINY_PNG = "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg=="
end
