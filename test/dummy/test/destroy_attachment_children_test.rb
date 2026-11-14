# frozen_string_literal: true

require "test_helper"
require "base64"
require "digest"
require "stringio"

class DestroyAttachmentChildrenTest < ActionDispatch::IntegrationTest
  BASE = "/recording_studio_api/api/v1"
  NOTIFICATION = RecordingStudioAttachable::DestroyAttachmentChildren::NOTIFICATION

  setup do
    @previous_actor = Current.actor
    @owner = user("owner")
    @editor = user("editor")
    Current.actor = @owner
    @workspace = Workspace.create!(name: "Destroy #{SecureRandom.hex(4)}")
    @root = RecordingStudio.root_recording_for(@workspace)
    @owner_access = bootstrap!(@root, @owner)
    @editor_access = grant!(@editor, :edit)
    @page = @root.record(Page, actor: @owner) { |page| page.title = "Notes" }
  end

  teardown do
    Current.actor = @previous_actor
  end

  test "the destroy callback is registered once and runs before child restrict" do
    assert_equal 1, attachment_destroy_callbacks.size
    refute RecordingStudioAttachable::DestroyAttachmentChildren.recording_destroys_recordable?

    2.times { RecordingStudio::Engine.apply_registered_extensions! }
    RecordingStudioAttachable::DestroyAttachmentChildren.register!
    RecordingStudio::Engine.apply_registered_extensions!
    RecordingStudio::Recording.include(RecordingStudioAttachable::DestroyAttachmentChildren::OnRecording)

    assert_equal 1, attachment_destroy_callbacks.size
    assert_operator callback_index, :<, child_restrict_index

    live = attach(@page, "live.png")
    @page.child_recordings.load
    assert @page.association(:child_recordings).loaded?
    assert_includes @page.child_recordings.map(&:id), live.id

    @page.destroy!

    assert_nil RecordingStudio::Recording.unscoped.find_by(id: @page.id)
    assert_nil RecordingStudio::Recording.unscoped.find_by(id: live.id)
  end

  test "a parent with live and trashed attachments destroys cleanly and notifies once" do
    live = attach(@page, "live.png")
    trashed = attach(@page, "trashed.png")
    previous_recordable_id = trashed.recordable_id
    trashed.revise_attachment_metadata(actor: @owner, caption: "Later")
    trashed.update!(trashed_at: Time.current)
    revised_recordable_id = trashed.reload.recordable_id
    live_recordable_id = live.recordable_id
    live_blob_id = live.recordable.file.blob.id
    event_ids = RecordingStudio::Event.unscoped.pluck(:id)

    payloads = []
    listener = lambda { |_name, _start, _finish, _id, payload| payloads << payload }
    ActiveSupport::Notifications.subscribed(listener, NOTIFICATION) do
      @page.destroy!
    end

    assert_equal 1, payloads.size
    assert_equal @page.id, payloads.first[:parent_recording_id]
    assert_equal 2, payloads.first[:count]
    assert_empty RecordingStudio::Event.unscoped.where.not(id: event_ids)
    assert_nil RecordingStudio::Recording.unscoped.find_by(id: live.id)
    assert_nil RecordingStudio::Recording.unscoped.find_by(id: trashed.id)
    assert_nil RecordingStudioAttachable::Attachment.find_by(id: live_recordable_id)
    assert_nil RecordingStudioAttachable::Attachment.find_by(id: previous_recordable_id)
    assert_nil RecordingStudioAttachable::Attachment.find_by(id: revised_recordable_id)
    assert_nil ActiveStorage::Blob.find_by(id: live_blob_id)
    assert Page.exists?(@page.recordable_id)
  end

  test "unshared blobs are purged and a shared recordable survives" do
    unshared = attach(@page, "only.png")
    shared = attach(@page, "shared.png")
    other = @root.record(Page, actor: @owner) { |page| page.title = "Other" }
    shared_recording = RecordingStudio.record!(
      action: "attachment_uploaded",
      recordable: shared.recordable,
      root_recording: @root,
      parent_recording: other,
      actor: @owner
    ).recording
    unshared_blob_id = unshared.recordable.file.blob.id
    shared_blob_id = shared.recordable.file.blob.id

    @page.destroy!

    assert_nil RecordingStudioAttachable::Attachment.find_by(id: unshared.recordable_id)
    assert_nil ActiveStorage::Blob.find_by(id: unshared_blob_id)
    assert RecordingStudioAttachable::Attachment.exists?(shared.recordable_id)
    assert RecordingStudio::Recording.unscoped.exists?(shared_recording.id)
    assert shared.recordable.reload.file.attached?
    assert_equal shared_blob_id, shared.recordable.file.blob.id
    assert ActiveStorage::Blob.exists?(shared_blob_id)
  end

  test "api destroy_resource removes a page that has attachments" do
    attachment = attach(@page, "api.png")
    blob_id = attachment.recordable.file.blob.id
    token = token_for(@editor_access)

    with_page_destroy_enabled do
      delete "#{BASE}/pages/#{@page.id}", headers: { "Authorization" => "Bearer #{token}", "Accept" => "application/json" }
    end

    assert_response :success
    assert_nil RecordingStudio::Recording.unscoped.find_by(id: @page.id)
    assert_nil RecordingStudio::Recording.unscoped.find_by(id: attachment.id)
    assert_nil RecordingStudioAttachable::Attachment.find_by(id: attachment.recordable_id)
    assert_nil ActiveStorage::Blob.find_by(id: blob_id)
  end

  private

  def attachment_destroy_callbacks
    RecordingStudio::Recording._destroy_callbacks.select do |callback|
      callback.filter == :recording_studio_attachable_destroy_attachment_children
    end
  end

  def callback_index
    destroy_filters.index(:recording_studio_attachable_destroy_attachment_children)
  end

  def child_restrict_index
    destroy_filters.index do |filter|
      next false unless filter.respond_to?(:source_location)

      source = filter.source_location&.first.to_s
      source.include?("/associations/")
    end
  end

  def destroy_filters
    RecordingStudio::Recording._destroy_callbacks.map(&:filter)
  end

  def attach(parent, filename)
    bytes = png_bytes
    blob = ActiveStorage::Blob.create_and_upload!(
      io: StringIO.new(bytes),
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

  def png_bytes
    Base64.decode64("iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==")
  end

  def user(name)
    User.create!(
      email: "#{name}-#{SecureRandom.hex(4)}@example.com",
      password: "Password123!",
      password_confirmation: "Password123!",
      name: name
    )
  end

  def bootstrap!(recording, actor)
    result = RecordingStudioAccessible.bootstrap_owner_access!(recording: recording, actor: actor)
    raise result.error if result.failure?

    result.value
  end

  def grant!(actor, role)
    result = RecordingStudioAccessible.grant_access(
      recording: @root,
      actor: actor,
      role: role,
      manager_actor: @owner
    )
    raise result.error if result.failure?

    result.value
  end

  def with_page_destroy_enabled
    registration = RecordingStudioApi::RecordableRegistration
    registration.prepend(PageDestroyOperation) unless registration.ancestors.include?(PageDestroyOperation)

    Thread.current[:recording_studio_attachable_page_destroy] = true
    yield
  ensure
    Thread.current[:recording_studio_attachable_page_destroy] = false
  end

  module PageDestroyOperation
    def supports_operation?(operation)
      return true if operation.to_sym == :destroy && recordable_type == "Page" && Thread.current[:recording_studio_attachable_page_destroy]

      super
    end
  end

  def token_for(access_recording)
    provision = RecordingStudioApi::Services::ProvisionApiClient.call(
      access_point_recording: access_recording.parent_recording || access_recording.root_recording,
      manager_actor: @owner,
      role: access_recording.recordable.role,
      name: "Client #{SecureRandom.hex(3)}"
    )
    raise provision.error unless provision.success?

    issued = RecordingStudioApi::Services::IssueOauthAccessToken.call(
      grant_type: "client_credentials",
      client_id: provision.value.fetch(:credential).oauth_client_id,
      client_secret: provision.value.fetch(:token)
    )
    raise issued.error unless issued.success?

    issued.value.fetch(:access_token)
  end
end
