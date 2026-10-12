# frozen_string_literal: true

require "test_helper"

class AttachableHostLocaleOverrideTest < ActionDispatch::IntegrationTest
  HOST_NOT_FOUND = "HOST Attachment resource not found"
  HOST_EMPTY_TITLE = "HOST Nothing uplaoded yet"
  OVERRIDE_KEY = "recording_studio.attachable.flashes.attachment_resource_not_found"
  EMPTY_TITLE_KEY = "recording_studio.attachable.library.empty_title"
  BOOT_HOST_LOCALE = Rails.root.join("config/locales/recording_studio_attachable_host.en.yml")
  FRESH_HOST_LOCALE = Rails.root.join("test/locales/attachable_host_override.en.yml")

  setup do
    @load_path_before = I18n.load_path.dup
    @backend_before = I18n.backend
  end

  teardown do
    assert_equal @load_path_before, I18n.load_path,
                 "test must not leave I18n.load_path modified"
  end

  # Real-boot-order guard: host file under config/locales must win without any
  # test-time load_path mutation.
  test "host locale override for recording_studio.attachable wins on boot order" do
    assert File.exist?(BOOT_HOST_LOCALE)
    assert_includes File.read(BOOT_HOST_LOCALE), HOST_NOT_FOUND
    assert_equal HOST_NOT_FOUND, I18n.t(OVERRIDE_KEY)
    assert_equal @load_path_before, I18n.load_path,
                 "boot-order test must not mutate I18n.load_path"
  end

  test "fresh-backend last-file-wins host fixture overrides gem english on library page" do
    assert File.exist?(FRESH_HOST_LOCALE), "expected test-only host override fixture at #{FRESH_HOST_LOCALE}"
    assert_includes File.read(FRESH_HOST_LOCALE), HOST_EMPTY_TITLE

    user = User.find_or_create_by!(email: "admin@admin.com") do |record|
      record.password = "Password"
      record.password_confirmation = "Password"
      record.name = "Avery"
    end
    sign_in user

    I18n.backend = I18n::Backend::Simple.new
    I18n.load_path = @load_path_before + [FRESH_HOST_LOCALE.to_s]
    I18n.backend.load_translations

    assert_equal HOST_EMPTY_TITLE, I18n.t(EMPTY_TITLE_KEY)
    assert_equal HOST_NOT_FOUND, I18n.t(OVERRIDE_KEY)

    workspace = Workspace.find_or_create_by!(name: "Host Override Empty #{SecureRandom.hex(4)}")
    Current.actor = user
    root = RecordingStudio.root_recording_for(workspace)
    grant_workspace_access!(root, user)
    library = RecordingStudioAttachable.library_for(root, actor: user)

    get recording_studio_attachable.recording_attachments_path(library)
    assert_response :success
    assert_includes response.body, HOST_EMPTY_TITLE
    refute_includes response.body, "HOST Library"
  ensure
    Current.actor = nil if defined?(Current)
    I18n.load_path = @load_path_before
    I18n.backend = @backend_before
  end

  private

  def grant_workspace_access!(root, user)
    original = RecordingStudioAccessible.configuration.access_management_authorizer
    RecordingStudioAccessible.configuration.access_management_authorizer = ->(**) { true }
    result = RecordingStudioAccessible.grant_access(
      recording: root,
      actor: user,
      role: :admin,
      manager_actor: user
    )
    raise result.error if result.failure?
  ensure
    RecordingStudioAccessible.configuration.access_management_authorizer = original
  end
end
