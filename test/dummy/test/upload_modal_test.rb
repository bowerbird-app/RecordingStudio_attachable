# frozen_string_literal: true

require "test_helper"

class UploadModalTest < ActionDispatch::IntegrationTest
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
    workspace = Workspace.find_or_create_by!(name: "Studio Workspace")
    Current.actor = @user
    @root = RecordingStudio.root_recording_for(workspace)
    grant_workspace_access!(@root)
    @original_presentation = RecordingStudioAttachable.configuration.upload_presentation
  end

  teardown do
    RecordingStudioAttachable.configuration.upload_presentation = @original_presentation
    Current.actor = nil if defined?(Current)
  end

  test "standard upload page keeps its layout and redirects after upload" do
    get recording_studio_attachable.recording_attachment_upload_path(@root)

    assert_response :success
    assert_includes response.body, "<html"
    assert_includes response.body, 'data-recording-studio-attachable--upload-success-behavior-value="redirect"'
    assert_includes response.body, "Choose files"
    assert_includes response.body, 'type="file" multiple'
    assert_includes response.body, 'data-recording-studio-attachable--upload-target="dropzone"'
    assert_includes response.body, 'data-recording-studio-attachable--upload-target="progressTemplate"'
    assert_not_includes response.body, "<turbo-frame"
  end

  test "upload modal request renders only the shared uploader inside the requesting frame" do
    get recording_studio_attachable.recording_attachment_upload_path(
      @root,
      embed: "upload_modal",
      frame_id: "my-upload-frame",
      redirect_mode: "return_to",
      return_to: "/attachment_editor"
    )

    assert_response :success
    assert_not_includes response.body, "<html"
    assert_match(/\A\s*<turbo-frame id="my-upload-frame">/, response.body)
    assert_includes response.body, 'data-recording-studio-attachable--upload-success-behavior-value="event"'
    assert_match(/data-recording-studio-attachable--upload-csrf-token-value="[^"]+"/, response.body)
    assert_includes response.body, "Choose files"
    assert_includes response.body, 'type="file" multiple'
    assert_includes response.body, 'data-recording-studio-attachable--upload-target="dropzone"'
    assert_includes response.body, 'data-recording-studio-attachable--upload-target="progressTemplate"'
    assert_includes response.body, "Drag and drop, or choose"
    assert_includes response.body, "Demo cloud import"
    assert_includes response.body, 'data-turbo-frame="_top"'
    assert_includes response.body, "return_to=%2Fattachment_editor"
  end

  test "upload modal ignores an unsafe frame id" do
    get recording_studio_attachable.recording_attachment_upload_path(
      @root, embed: "upload_modal", frame_id: "\"><script>"
    )

    assert_response :success
    assert_includes response.body, %(<turbo-frame id="attachable-upload-modal-#{@root.id}-frame">)
    assert_not_includes response.body, "<script>"
  end

  test "upload modal leaves out providers that open their own modal page" do
    configuration = RecordingStudioAttachable.configuration
    configuration.register_upload_provider(
      :modal_demo, label: "Modal demo", url: "/upload_providers/demo", strategy: :modal_page
    )

    get recording_studio_attachable.recording_attachment_upload_path(@root)
    assert_includes response.body, "Modal demo"
    assert_includes response.body, "data-provider-modal-frame"

    get recording_studio_attachable.recording_attachment_upload_path(@root, embed: "upload_modal")
    assert_not_includes response.body, "Modal demo"
    assert_not_includes response.body, "data-provider-modal-frame"
  ensure
    configuration.upload_providers = configuration.upload_providers.reject { |provider| provider.key == :modal_demo }
  end

  test "editor upload button opens the uploader in a modal with a lazy frame" do
    get attachment_editor_path

    assert_response :success
    modal_id = "attachable-upload-modal-#{@root.id}"
    assert_includes response.body, 'data-controller="recording-studio-attachable--upload-modal"'
    assert_includes response.body, %(data-modal-id="#{modal_id}")
    assert_includes response.body, %(id="#{modal_id}")
    assert_includes response.body, %(<turbo-frame id="#{modal_id}-frame")
    assert_includes response.body, 'loading="lazy"'
    assert_includes response.body, "embed=upload_modal"
    assert_includes response.body, "Add files"
    assert_includes response.body, 'id="attachment-editor-images"'
  end

  test "file buttons follow the global upload presentation unless they override it" do
    assert_includes render_add_button, "recording-studio-attachable--attachment-revision-upload"

    RecordingStudioAttachable.configuration.upload_presentation = :modal
    modal_html = render_add_button
    assert_includes modal_html, "recording-studio-attachable--upload-modal"
    assert_not_includes modal_html, "recording-studio-attachable--attachment-revision-upload"

    assert_includes render_add_button(presentation: :page), "recording-studio-attachable--attachment-revision-upload"
  end

  test "change mode stays inline even when the modal is requested" do
    html = render_add_button(presentation: :modal, attachment_recording: @root)

    assert_includes html, "recording-studio-attachable--attachment-revision-upload"
    assert_not_includes html, "recording-studio-attachable--upload-modal"
  end

  private

  def render_add_button(attachment_recording: nil, **options)
    locals = RecordingStudioAttachable::AttachmentFileButton.locals(
      recording: @root, return_to: "/attachment_editor", **options
    ).merge(attachment_recording: attachment_recording)
    RecordingStudioAttachable::ApplicationController.render(
      partial: "recording_studio_attachable/attachment_file_buttons/button",
      locals: locals
    )
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
end
