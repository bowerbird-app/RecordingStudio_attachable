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

  test "attachment upload page emits unescaped launcher module imports" do
    prepare_workspace!

    with_client_picker_providers_registered do
      get recording_studio_attachable.recording_attachment_upload_path(@root)
      assert_response :success
      assert_unescaped_launcher_imports(response.body)
    end
  end

  test "image picker modal emits unescaped launcher module imports" do
    prepare_workspace!
    page = Page.find_or_create_by!(title: "Home page")
    RecordingStudio::Recording.unscoped.find_or_create_by!(
      root_recording_id: @root.id,
      parent_recording_id: @root.id,
      recordable: page
    )

    with_client_picker_providers_registered do
      get edit_page_path(page)
      assert_response :success
      assert_unescaped_launcher_imports(response.body)
    end
  end

  private

  def prepare_workspace!
    workspace = Workspace.find_or_create_by!(name: "Studio Workspace")
    Current.actor = @user
    @root = RecordingStudio.root_recording_for(workspace)
    grant_workspace_access!(@root)
  end

  def with_client_picker_providers_registered
    configuration = RecordingStudioAttachable.configuration
    original_providers = configuration.upload_providers.dup
    configuration.register_upload_provider(
      :my_cloud,
      label: "My Cloud",
      url: "/my-cloud-bootstrap",
      strategy: :client_picker,
      launcher: "my_cloud",
      launcher_module: "my_cloud/picker_launcher",
      remote_importer: ->(**) {}
    )
    configuration.register_upload_provider(
      :extra_cloud,
      label: "Extra Cloud",
      url: "/extra-cloud-bootstrap",
      strategy: :client_picker,
      launcher: "extra_cloud",
      launcher_module: "extra_cloud/picker_launcher",
      remote_importer: ->(**) {}
    )
    yield
  ensure
    configuration.upload_providers = original_providers
  end

  def assert_unescaped_launcher_imports(html)
    assert_includes html, %(import "my_cloud/picker_launcher")
    assert_includes html, %(import "extra_cloud/picker_launcher")
    refute_match(/import &quot;/, html)

    scripts = html.scan(%r{<script\b[^>]*type="module"[^>]*>.*?</script>}m)
    launcher_scripts = scripts.select { |script| script.include?(%(import "my_cloud/picker_launcher")) || script.include?(%(import "extra_cloud/picker_launcher")) }
    assert_operator launcher_scripts.size, :>=, 2, "expected both launcher scripts"

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
