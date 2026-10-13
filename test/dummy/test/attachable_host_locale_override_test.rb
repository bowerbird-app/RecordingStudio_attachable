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
    I18n.backend = @backend_before if @backend_before
    assert_equal @load_path_before, I18n.load_path,
                 "test must not leave I18n.load_path modified"
  end

  # Real-boot-order guard: host file under config/locales must win without any
  # test-time load_path mutation. Render assertion uses the not-found flash.
  test "host locale override for recording_studio.attachable wins on boot order" do
    assert File.exist?(BOOT_HOST_LOCALE)
    assert_includes File.read(BOOT_HOST_LOCALE), HOST_NOT_FOUND
    assert_equal HOST_NOT_FOUND, I18n.t(OVERRIDE_KEY)
    assert_equal @load_path_before, I18n.load_path,
                 "boot-order test must not mutate I18n.load_path"

    user = User.find_or_create_by!(email: "admin@admin.com") do |record|
      record.password = "Password"
      record.password_confirmation = "Password"
      record.name = "Avery"
    end
    sign_in user

    get recording_studio_attachable.attachment_path("00000000-0000-0000-0000-000000000000")
    assert_response :redirect
    assert_equal HOST_NOT_FOUND, flash[:alert]
  end

  # Test-only fixture applied via backend.load_translations(file) on top of the
  # already-initialized backend — never mutates I18n.load_path (Marshal).
  test "fresh-backend last-file-wins host fixture overrides gem english on library page" do
    assert File.exist?(FRESH_HOST_LOCALE), "expected test-only host override fixture at #{FRESH_HOST_LOCALE}"
    assert_includes File.read(FRESH_HOST_LOCALE), HOST_EMPTY_TITLE

    user = User.find_or_create_by!(email: "admin@admin.com") do |record|
      record.password = "Password"
      record.password_confirmation = "Password"
      record.name = "Avery"
    end
    sign_in user

    snapshot = i18n_backend_translations_snapshot
    # Force default load_path translations into the backend, then layer the
    # test-only fixture last without touching I18n.load_path.
    I18n.t(EMPTY_TITLE_KEY)
    I18n.backend.load_translations(FRESH_HOST_LOCALE.to_s)

    assert_equal @load_path_before, I18n.load_path
    assert_equal HOST_EMPTY_TITLE, I18n.t(EMPTY_TITLE_KEY)
    assert_equal HOST_NOT_FOUND, I18n.t(OVERRIDE_KEY)

    workspace = Workspace.find_or_create_by!(name: "Host Override Empty #{SecureRandom.hex(4)}")
    Current.actor = user
    root = RecordingStudio.root_recording_for(workspace)
    grant_workspace_access!(root, user)

    get recording_studio_attachable.recording_attachments_path(root)
    assert_response :success
    assert_includes response.body, HOST_EMPTY_TITLE
    refute_includes response.body, "HOST Library"
  ensure
    Current.actor = nil if defined?(Current)
    restore_i18n_backend_translations(snapshot) if snapshot
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

  def i18n_backend_translations_snapshot
    backend = I18n.backend
    backend.send(:init_translations) unless backend.initialized?
    translations =
      if backend.respond_to?(:translations)
        backend.translations
      else
        backend.instance_variable_get(:@translations)
      end
    return unless translations

    deep_plain_copy(translations)
  end

  def restore_i18n_backend_translations(snapshot)
    backend = I18n.backend
    backend.instance_variable_set(:@translations, snapshot)
    backend.instance_variable_set(:@initialized, true) if backend.instance_variable_defined?(:@initialized)
  end

  def deep_plain_copy(value)
    case value
    when Hash
      value.each_with_object({}) { |(key, nested), copy| copy[key] = deep_plain_copy(nested) }
    when Array
      value.map { |nested| deep_plain_copy(nested) }
    else
      value
    end
  end
end
