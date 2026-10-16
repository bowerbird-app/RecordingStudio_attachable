# frozen_string_literal: true

require "test_helper"
require "base64"
require "digest"

class DirectUploadTest < ActionDispatch::IntegrationTest
  setup do
    @user = User.create!(
      email: "uploader-#{SecureRandom.hex(4)}@example.com",
      password: "Password123!",
      password_confirmation: "Password123!",
      name: "Uploader"
    )
    sign_in @user
    Current.actor = @user
    workspace = Workspace.create!(name: "Uploads #{SecureRandom.hex(4)}")
    @root = RecordingStudio.root_recording_for(workspace)
    grant_workspace_access!(@root)
  end

  teardown do
    Current.actor = nil if defined?(Current)
  end

  test "the recording direct upload binds the blob and a rails signed id is refused" do
    bytes = Base64.decode64("iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==")
    post recording_studio_attachable.recording_direct_uploads_path(@root),
         params: { blob: { filename: "photo.png", byte_size: bytes.bytesize, checksum: checksum(bytes), content_type: "image/png" } },
         as: :json
    assert_response :success, response.body
    ticket = JSON.parse(response.body)
    assert ticket["signed_id"].present?
    put_upload(ticket, bytes)

    post "/recording_studio_attachable/recordings/#{@root.id}/attachments",
         params: { attachments: [{ signed_blob_id: ticket.fetch("signed_id"), name: "Door" }] },
         as: :json
    assert_response :created, response.body
    body = JSON.parse(response.body)
    recording_id = body.fetch("attachments").first.fetch("id")

    forged = ActiveStorage::Blob.create_before_direct_upload!(
      filename: "other.png", byte_size: bytes.bytesize, checksum: checksum(bytes), content_type: "image/png"
    )
    post "/recording_studio_attachable/recordings/#{@root.id}/attachments",
         params: { attachments: [{ signed_blob_id: forged.signed_id, name: "Foreign" }] },
         as: :json
    assert_response :unprocessable_content

    get recording_studio_attachable.attachment_file_path(recording_id)
    assert_response :success
    assert_equal "sandbox", response.headers["Content-Security-Policy"]
    assert_equal "nosniff", response.headers["X-Content-Type-Options"]
    assert_includes response.headers["Content-Disposition"], "inline"
  end

  private

  def checksum(bytes)
    Base64.strict_encode64(Digest::MD5.digest(bytes))
  end

  def put_upload(ticket, bytes)
    uri = URI(ticket.dig("direct_upload", "url"))
    put "#{uri.path}?#{uri.query}", params: bytes, headers: ticket.dig("direct_upload", "headers")
    assert_response :no_content, response.body
  end

  def grant_workspace_access!(root)
    original = RecordingStudioAccessible.configuration.access_management_authorizer
    RecordingStudioAccessible.configuration.access_management_authorizer = ->(**) { true }
    result = RecordingStudioAccessible.grant_access(recording: root, actor: @user, role: :admin, manager_actor: @user)
    raise result.error if result.failure?
  ensure
    RecordingStudioAccessible.configuration.access_management_authorizer = original
  end
end
