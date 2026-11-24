# frozen_string_literal: true

require "test_helper"
require "base64"
require "stringio"

class TrashedAttachmentReadTest < ActionDispatch::IntegrationTest
  PNG = Base64.decode64("iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==")

  setup do
    @previous_actor = Current.actor
    password = "Password123!"
    @owner = User.create!(
      email: "owner-#{SecureRandom.hex(4)}@example.com",
      password: password,
      password_confirmation: password,
      name: "Owner"
    )
    @viewer = User.create!(
      email: "viewer-#{SecureRandom.hex(4)}@example.com",
      password: password,
      password_confirmation: password,
      name: "Viewer"
    )
    sign_in @owner
    Current.actor = @owner
    workspace = Workspace.create!(name: "Trash reads #{SecureRandom.hex(4)}")
    @root = RecordingStudio.create_root_recording!(workspace, actor: @owner)
    bootstrap!(@root, @owner)
    grant!(@viewer, :view)
    @page = @root.record(Page, actor: @owner) { |page| page.title = "Notes" }
    @attachment = attach_image(@root, "live.png")
    process_preview(@attachment)
  end

  teardown do
    Current.actor = @previous_actor
    clear_public_reads!
  end

  test "a published attachment is anonymously readable and a removed one is not" do
    grant_public_reads!(true)
    sign_out @owner
    assert_public_bytes(@attachment)

    sign_in @owner
    Current.actor = @owner
    removed = RecordingStudioAttachable::Services::RemoveAttachment.call(
      attachment_recording: @attachment,
      actor: @owner
    )
    assert removed.success?, removed.error.to_s

    sign_out @owner
    get recording_studio_attachable.attachment_file_path(@attachment)
    assert_response :not_found

    sign_in @viewer
    get recording_studio_attachable.attachment_file_path(@attachment)
    assert_response :not_found

    sign_in @owner
    get recording_studio_attachable.attachment_preview_file_path(@attachment, variant_name: "large")
    assert_response :success
    assert_operator response.body.bytesize, :>, 0
  end

  test "anonymous byte reads are refused when the owner is unpublished" do
    grant_public_reads!(false)
    sign_out @owner

    each_byte(@attachment) do
      assert_response :not_found
      assert_not_equal PNG, response.body
    end
  end

  test "anonymous byte reads are refused without a view role on a non-public owner" do
    sign_out @owner

    each_byte(@attachment) do
      refute_equal 200, response.status
      assert_not_equal PNG, response.body
    end
  end

  test "a child under a trashed ancestor is not anonymously readable" do
    child = attach_image(@page, "nested.png")
    @page.update!(trashed_at: Time.current)

    sign_out @owner
    get recording_studio_attachable.attachment_file_path(child)
    assert_response :not_found
  end

  test "a trashed attachment omits the file url for a viewer and keeps it for an admin" do
    RecordingStudioAttachable.configuration.public_url_host = "files.example.test"
    removed = RecordingStudioAttachable::Services::RemoveAttachment.call(
      attachment_recording: @attachment,
      actor: @owner
    )
    assert removed.success?, removed.error.to_s

    hidden = RecordingStudioAttachable.attachment_payload(@attachment, actor: @viewer)
    visible = RecordingStudioAttachable.attachment_payload(@attachment, actor: @owner)

    assert_nil hidden.dig(:urls, :file)
    assert_nil hidden.dig(:urls, :file_url)
    assert visible.dig(:urls, :file).present?
    assert_match(%r{\Ahttps://files\.example\.test/}, visible.dig(:urls, :file_url))
  ensure
    RecordingStudioAttachable.configuration.public_url_host = nil
  end

  private

  def attach_image(parent, filename)
    blob = ActiveStorage::Blob.create_and_upload!(
      io: StringIO.new(PNG),
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
      parent_recording: parent,
      actor: @owner
    ).recording
  end

  def process_preview(recording)
    target = recording.recordable.preview_target_named(:large)
    raise "preview target missing" if target.blank?

    target.processed
  end

  def each_byte(recording)
    [
      recording_studio_attachable.attachment_file_path(recording),
      recording_studio_attachable.download_attachment_path(recording),
      recording_studio_attachable.attachment_preview_file_path(recording, variant_name: "large")
    ].each do |path|
      get path
      yield
    end
  end

  def assert_public_bytes(recording)
    get recording_studio_attachable.attachment_file_path(recording)
    assert_response :success
    assert_equal PNG, response.body

    get recording_studio_attachable.download_attachment_path(recording)
    assert_response :success
    assert_equal PNG, response.body

    get recording_studio_attachable.attachment_preview_file_path(recording, variant_name: "large")
    assert_response :success
    assert_operator response.body.bytesize, :>, 0
  end

  def grant_public_reads!(published)
    Workspace.define_method(:attachable_available_for?) { |**| published }
    @previous_authorizer = RecordingStudioAttachable.configuration.authorize_with
    RecordingStudioAttachable.configuration.authorize_with = lambda do |action:, actor:, recording:, role:|
      if actor.blank?
        %i[view download].include?(action.to_sym)
      else
        RecordingStudioAccessible::Authorization.allowed?(actor: actor, recording: recording, role: role)
      end
    end
  end

  def clear_public_reads!
    RecordingStudioAttachable.configuration.authorize_with = @previous_authorizer if defined?(@previous_authorizer)
    return unless Workspace.method_defined?(:attachable_available_for?)

    Workspace.remove_method(:attachable_available_for?)
  end

  def bootstrap!(recording, actor)
    authorizer = RecordingStudioAccessible.configuration.access_management_authorizer
    RecordingStudioAccessible.configuration.access_management_authorizer = ->(**) { true }
    result = RecordingStudioAccessible.bootstrap_owner_access!(recording: recording, actor: actor)
    raise result.error if result.failure?
  ensure
    RecordingStudioAccessible.configuration.access_management_authorizer = authorizer
  end

  def grant!(actor, role)
    authorizer = RecordingStudioAccessible.configuration.access_management_authorizer
    RecordingStudioAccessible.configuration.access_management_authorizer = ->(**) { true }
    result = RecordingStudioAccessible.grant_access(
      recording: @root,
      actor: actor,
      role: role,
      manager_actor: @owner
    )
    raise result.error if result.failure?
  ensure
    RecordingStudioAccessible.configuration.access_management_authorizer = authorizer
  end
end
