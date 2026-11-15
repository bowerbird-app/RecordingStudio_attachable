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
    page.execute_script(<<~JS)
      window.__attachableUploaded = []
      document.addEventListener("attachable:uploaded", (event) => {
        window.__attachableUploaded.push({
          attachments: event.detail && event.detail.attachments,
          redirectPath: event.detail && event.detail.redirectPath
        })
      }, true)
    JS
    click_on "Add files"

    within "##{modal_id}" do
      assert_text "Upload a file", wait: 10
      assert_text "or drag and drop"
      assert_no_text "Back"
      drop_disallowed_file
      assert_text "notes.txt"
      assert_text "not allowed"
      attach_file [png_file(first_name), png_file(second_name)], make_visible: true
    end

    assert_no_selector "##{modal_id}", visible: true, wait: 20
    uploaded = page.evaluate_script("window.__attachableUploaded[0]")
    assert uploaded.present?
    assert_kind_of Array, uploaded["attachments"]
    assert uploaded["redirectPath"].present?
    assert_current_path attachment_editor_path
    # The list shows each image. Caption fields do not include the file name, so the refreshed row is the visible alt.
    assert_selector "turbo-frame#attachment-editor-images img[alt='#{File.basename(first_name, ".*")}']", wait: 10
    assert_selector "turbo-frame#attachment-editor-images img[alt='#{File.basename(second_name, ".*")}']"
  end

  test "the dropzone keeps only the first max_files selection" do
    visit recording_studio_attachable.recording_attachment_upload_path(@root)
    assert_text "Upload a file", wait: 10

    max_files = page.evaluate_script(<<~JS)
      document.querySelector("[data-controller~='flat-pack--file-input']")
        ?.getAttribute("data-flat-pack--file-input-max-files-value")
    JS
    assert_equal "20", max_files

    names = (1..(max_files.to_i + 1)).map { |index| "capped-#{index}.zip" }
    page.execute_script(<<~JS)
      const names = #{names.to_json}
      const zone = document.querySelector("[data-controller~='flat-pack--file-input']")
      const dataTransfer = new DataTransfer()
      names.forEach((name) => {
        dataTransfer.items.add(new File(["hello"], name, { type: "application/zip" }))
      })
      zone.dispatchEvent(new DragEvent("drop", { bubbles: true, cancelable: true, dataTransfer }))
    JS

    assert_text "Only the first 20 files were kept.", wait: 5
    assert_text "capped-1.zip"
    assert_text "capped-20.zip"
    assert_no_text "capped-21.zip"
  end

  test "the file button uploads the chosen file and stays on the page" do
    page_recording = ensure_page!
    clear_attachments!(page_recording)
    filename = "file-button-#{SecureRandom.hex(4)}.png"
    visit attachment_chromes_path

    within "#page-file-button" do
      assert_selector "button", text: "Add"
      assert_selector "input.sr-only[type='file']", visible: :all
      attach_file png_file(filename), make_visible: true
    end

    expected_name = File.basename(filename, ".*")
    assert_current_path attachment_chromes_path, wait: 20
    attached = wait_for_attachment_named(page_recording, expected_name)
    within "#page-file-button" do
      assert_selector "button", text: "Change", wait: 10
    end
    assert_equal expected_name, attached.recordable.name
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
      const zone = document.querySelector("[data-controller~='flat-pack--file-input']")
      const file = new File(["hello"], "notes.txt", { type: "application/zip" })
      const dataTransfer = new DataTransfer()
      dataTransfer.items.add(file)
      zone.dispatchEvent(new DragEvent("drop", { bubbles: true, cancelable: true, dataTransfer }))
    JS
  end

  def uploader_connected?
    page.evaluate_script(<<~JS)
      (() => {
        const zone = document.querySelector("[data-controller~='flat-pack--file-input']")
        const stimulus = window.Stimulus
        return Boolean(stimulus && zone && stimulus.getControllerForElementAndIdentifier(zone, "flat-pack--file-input"))
      })()
    JS
  end

  def png_file(name)
    path = Rails.root.join("tmp", name)
    FileUtils.mkdir_p(path.dirname)
    File.binwrite(path, Base64.decode64(TINY_PNG))
    path.to_s
  end

  def clear_attachments!(page_recording)
    existing = page_recording.attachments(scope: :direct, per_page: 50).to_a
    return if existing.empty?

    page_recording.remove_attachments(attachment_recordings: existing, actor: @user)
  end

  def wait_for_attachment_named(page_recording, name)
    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 20
    loop do
      attached = RecordingStudio::Recording.uncached do
        page_recording.attachments(scope: :direct, per_page: 50).find { |recording| recording.recordable.name == name }
      end
      return attached if attached
      raise "attachment #{name} was not saved" if Process.clock_gettime(Process::CLOCK_MONOTONIC) > deadline

      sleep 0.2
    end
  end

  def ensure_page!
    page = Page.first || Page.create!(title: "Chrome page")
    root = RecordingStudio.root_recording_for(Workspace.first!)
    RecordingStudio::Recording.unscoped.find_or_create_by!(
      root_recording_id: root.id,
      recordable: page
    ) do |recording|
      recording.parent_recording_id = root.id
    end
  end

  def grant_workspace_access!(root)
    original = RecordingStudioAccessible.configuration.access_management_authorizer
    RecordingStudioAccessible.configuration.access_management_authorizer = ->(**) { true }
    result = RecordingStudioAccessible.bootstrap_owner_access!(recording: root, actor: @user)
    raise result.error if result.failure?
  ensure
    RecordingStudioAccessible.configuration.access_management_authorizer = original
  end

  TINY_PNG = "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg=="
end
