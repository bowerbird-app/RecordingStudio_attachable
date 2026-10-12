# frozen_string_literal: true

require "test_helper"

class UploadProviderLauncherScriptsTest < ActionDispatch::IntegrationTest
  setup do
    @user = User.find_by(email: "admin@admin.com")
    if @user.blank?
      @user = User.new(
        email: "admin@admin.com",
        password: "Password",
        password_confirmation: "Password",
        name: "Avery"
      )
      @user.save!
    end
    sign_in @user
  end

  test "library upload page emits unescaped launcher module imports" do
    library = prepare_library!

    with_client_picker_providers_registered do
      get recording_studio_attachable.recording_attachment_upload_path(library)
      assert_response :success
      assert_unescaped_launcher_imports(response.body)
    end
  end

  test "image picker modal emits unescaped launcher module imports" do
    prepare_library!
    gallery = Gallery.find_or_create_by!(title: "Kiln shots")
    RecordingStudio::Recording.unscoped.find_or_create_by!(
      root_recording_id: @root.id,
      parent_recording_id: @root.id,
      recordable: gallery
    )

    with_client_picker_providers_registered do
      get gallery_path(gallery)
      assert_response :redirect
      follow_redirect!
      assert_response :success
      assert_unescaped_launcher_imports(response.body)
    end
  end

  private

  def prepare_library!
    workspace = Workspace.find_or_create_by!(name: "Studio Workspace")
    Current.actor = @user
    @root = RecordingStudio.root_recording_for(workspace)
    grant_workspace_access!(@root)
    RecordingStudioAttachable.library_for(@root, actor: @user)
  end

  def with_client_picker_providers_registered
    configuration = RecordingStudioAttachable.configuration
    original_providers = configuration.upload_providers.dup
    configuration.register_upload_provider(
      :google_drive,
      label: "Google Drive",
      url: "/google-drive-bootstrap",
      strategy: :client_picker,
      launcher: "google_drive",
      launcher_module: "controllers/recording_studio_attachable/google_drive_picker_launcher",
      remote_importer: ->(**) {}
    )
    configuration.register_upload_provider(
      :dropbox,
      label: "Dropbox",
      url: "/dropbox-bootstrap",
      strategy: :client_picker,
      launcher: "dropbox",
      launcher_module: "controllers/recording_studio_attachable/dropbox_picker_launcher",
      remote_importer: ->(**) {}
    )
    yield
  ensure
    configuration.instance_variable_set(:@upload_providers, original_providers)
  end

  def assert_unescaped_launcher_imports(html)
    assert_includes html, %(import "controllers/recording_studio_attachable/google_drive_picker_launcher")
    assert_includes html, %(import "controllers/recording_studio_attachable/dropbox_picker_launcher")
    refute_match(/import &quot;controllers\/recording_studio_attachable\//, html)

    scripts = html.scan(%r{<script\b[^>]*type="module"[^>]*>.*?</script>}m)
    launcher_scripts = scripts.select { |script| script.include?(%(import "controllers/recording_studio_attachable/)) }
    assert_operator launcher_scripts.size, :>=, 2, "expected Drive and Dropbox launcher scripts"

    launcher_scripts.each do |script|
      refute_includes script, "&quot;"
    end
  end

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
