# frozen_string_literal: true

require "application_system_test_case"
require Rails.root.join("../../test/support/oversized_png")

class ImageLimitsSystemTest < ApplicationSystemTestCase
  self.use_transactional_tests = false

  setup do
    @user = User.find_by(email: "admin@admin.com") || User.create!(
      email: "admin@admin.com", password: "Password", password_confirmation: "Password", name: "Avery"
    )
    @workspace = Workspace.find_or_create_by!(name: "Studio Workspace")
    Current.actor = @user
    @root = RecordingStudio.create_root_recording!(@workspace, actor: @user)
    grant_workspace_access!(@root)
    login_as @user, scope: :user
  end

  test "the uploader warns and does not request a ticket for an over cap image" do
    use_desktop
    visit upload_path
    assert_text "Upload a file", wait: 10
    watch_direct_uploads
    attach_file wide_png, make_visible: true

    assert_text "This image is too big", wait: 10
    assert_text "12,000"
    assert_equal 0, direct_upload_requests
    reveal_warning
    save_app_screenshot("image-too-large-desktop")
  end

  test "a normal image still uploads" do
    use_desktop
    filename = "within-cap-#{SecureRandom.hex(4)}.png"
    visit upload_path
    assert_text "Upload a file", wait: 10
    attach_file tiny_png(filename), make_visible: true

    assert_current_path "/attachment_editor", wait: 20
    assert_selector "img[alt='#{File.basename(filename, ".*")}']"
    assert_no_text "This image is too big"
    save_app_screenshot("image-upload-ok-desktop")
  end

  test "the warning still shows on a narrow screen" do
    use_narrow
    visit upload_path
    assert_text "Upload a file", wait: 10
    attach_file wide_png, make_visible: true

    assert_text "This image is too big", wait: 10
    assert_text "12,000"
    reveal_warning
    save_app_screenshot("image-too-large-narrow")
  end

  private

  def use_desktop
    page.current_window.resize_to(1400, 1000)
  end

  def use_narrow
    page.current_window.resize_to(390, 844)
  end

  def reveal_warning
    page.execute_script(<<~JS)
      document.querySelector(".text-red-600")?.scrollIntoView({ block: "center" })
    JS
  end

  def save_app_screenshot(name)
    directory = Rails.root.join("../../docs/images")
    FileUtils.mkdir_p(directory)
    page.save_screenshot(directory.join("#{name}.png").to_s)
  end

  def upload_path
    recording_studio_attachable.recording_attachment_upload_path(
      @root, redirect_mode: "return_to", return_to: "/attachment_editor"
    )
  end

  def watch_direct_uploads
    page.execute_script(<<~JS)
      window.__directUploadRequests = 0
      const open = XMLHttpRequest.prototype.open
      XMLHttpRequest.prototype.open = function(method, url) {
        if (String(url).includes("direct_upload")) window.__directUploadRequests += 1
        return open.apply(this, arguments)
      }
    JS
  end

  def direct_upload_requests
    page.evaluate_script("window.__directUploadRequests")
  end

  def wide_png
    path = Rails.root.join("tmp", "over-cap-wide.png")
    FileUtils.mkdir_p(path.dirname)
    File.binwrite(path, OversizedPng.bytes(13_000, 1, valid: true))
    path.to_s
  end

  def tiny_png(name)
    path = Rails.root.join("tmp", name)
    FileUtils.mkdir_p(path.dirname)
    File.binwrite(path, OversizedPng.bytes(480, 320, valid: true, fill: 30))
    path.to_s
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
