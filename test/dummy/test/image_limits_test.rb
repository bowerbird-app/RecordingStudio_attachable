# frozen_string_literal: true

require "test_helper"
require "base64"
require "digest"
require "rack/test"
require Rails.root.join("../../test/support/oversized_png")

class ImageLimitsTest < ActionDispatch::IntegrationTest
  setup do
    @user = User.create!(
      email: "limits-#{SecureRandom.hex(4)}@example.com",
      password: "Password123!",
      password_confirmation: "Password123!",
      name: "Limits"
    )
    sign_in @user
    Current.actor = @user
    workspace = Workspace.create!(name: "Limits #{SecureRandom.hex(4)}")
    @root = RecordingStudio.create_root_recording!(workspace, actor: @user)
    grant_workspace_access!(@root)
    @configuration = RecordingStudioAttachable.configuration
    @pixels = @configuration.max_image_pixels
    @side = @configuration.max_image_longest_side
    @url_mode = @configuration.url_mode
    @direct_host = @configuration.direct_url_host
  end

  teardown do
    Current.actor = nil if defined?(Current)
    @configuration.max_image_pixels = @pixels
    @configuration.max_image_longest_side = @side
    @configuration.url_mode = @url_mode
    @configuration.direct_url_host = @direct_host
    ActiveJob::Base.queue_adapter = @previous_adapter if @previous_adapter
  end

  test "an over cap image is refused on attach replace and import and no attachment remains" do
    bomb = OversizedPng.bytes(13_000, 1, valid: true)
    before = attachment_count

    ticket = upload_ticket("wide.png", bomb)
    put_upload(ticket, bomb)
    stored_id = blob_id(ticket)
    post attachments_path, params: { attachments: [{ signed_blob_id: ticket.fetch("signed_id"), name: "Wide" }] }, as: :json

    assert_response :unprocessable_content
    assert_includes json.fetch("error"), "too big"
    assert_includes json.fetch("error"), "12,000"
    assert_equal before, attachment_count
    assert_nil ActiveStorage::Blob.find_by(id: stored_id)

    kept = attach_bytes("photo.png", OversizedPng.bytes(8, 8, valid: true))
    replacement = upload_ticket("replacement.png", bomb)
    put_upload(replacement, bomb)
    replacement_id = blob_id(replacement)
    patch recording_studio_attachable.attachment_path(kept.fetch("id")),
          params: { attachment: { signed_blob_id: replacement.fetch("signed_id"), name: "Photo" } }

    assert_response :see_other
    assert_includes flash[:alert], "too big"
    assert_equal before + 1, attachment_count
    assert_nil ActiveStorage::Blob.find_by(id: replacement_id)

    post recording_studio_attachable.recording_attachment_imports_path(@root),
         params: { attachment_import: { attachments: [{ file: uploaded("bomb.png", bomb), name: "Bomb" }] } }
    assert_response :see_other
    assert_includes flash[:alert], "too big"
    assert_equal before + 1, attachment_count
  end

  test "an image under the cap is accepted and still gets small med and large" do
    created = attach_bytes("small.png", OversizedPng.bytes(8, 8, valid: true))
    attachment = RecordingStudio::Recording.find(created.fetch("id")).recordable

    perform_enqueued_jobs only: RecordingStudioAttachable::PreprocessVariantsJob

    assert attachment.variant_processed?(:small)
    assert attachment.variant_processed?(:med)
    assert attachment.variant_processed?(:large)
  end

  test "an existing over cap attachment skips variants and never serves the original as a preview" do
    @previous_adapter = ActiveJob::Base.queue_adapter
    ActiveJob::Base.queue_adapter = :test
    created = attach_bytes("stored.png", OversizedPng.bytes(8, 8, valid: true))
    recording = RecordingStudio::Recording.find(created.fetch("id"))
    clear_enqueued_jobs
    @configuration.max_image_longest_side = 2

    assert_nothing_raised do
      RecordingStudioAttachable::PreprocessVariantsJob.perform_now(recording.recordable.id)
    end
    assert_not recording.recordable.reload.variant_processed?(:small)

    get recording_studio_attachable.attachment_preview_file_path(recording, variant_name: "large")
    assert_response :not_found
    assert_not_equal OversizedPng.bytes(8, 8, valid: true), response.body

    get recording_studio_attachable.attachment_file_path(recording)
    assert_response :success

    @configuration.url_mode = :direct
    @configuration.direct_url_host = "images.example.test"
    url = nil
    assert_no_enqueued_jobs only: RecordingStudioAttachable::PreprocessVariantsJob do
      url = recording.recordable.url_for_variant(:large, rails_url: "/preview/large")
    end
    assert_equal "/preview/large", url
    assert_no_match(%r{images\.example\.test}, url)
  end

  test "an unknown variant name is a 404" do
    created = attach_bytes("known.png", OversizedPng.bytes(8, 8, valid: true))

    get recording_studio_attachable.attachment_preview_file_path(created.fetch("id"), variant_name: "no-such-size")

    assert_response :not_found
  end

  test "host overrides for both caps refuse and allow through the upload" do
    photo = OversizedPng.bytes(8, 8, valid: true)
    @configuration.max_image_pixels = 10
    refused = upload_ticket("pixels.png", photo)
    put_upload(refused, photo)
    post attachments_path, params: { attachments: [{ signed_blob_id: refused.fetch("signed_id"), name: "Pixels" }] }, as: :json
    assert_response :unprocessable_content
    assert_includes json.fetch("error"), "10"

    @configuration.max_image_pixels = @pixels
    @configuration.max_image_longest_side = 4
    refused_side = upload_ticket("side.png", photo)
    put_upload(refused_side, photo)
    post attachments_path, params: { attachments: [{ signed_blob_id: refused_side.fetch("signed_id"), name: "Side" }] }, as: :json
    assert_response :unprocessable_content
    assert_includes json.fetch("error"), "4"

    @configuration.max_image_longest_side = @side
    assert attach_bytes("fits.png", photo).fetch("id").present?
  end

  test "the upload page gives the browser both caps and the warning" do
    get recording_studio_attachable.recording_attachment_upload_path(@root)

    assert_response :success
    assert_includes response.body, 'max-image-pixels-value="40000000"'
    assert_includes response.body, 'max-image-longest-side-value="12000"'
    assert_includes response.body, "40,000,000"
    assert_includes response.body, "12,000"
  end

  private

  def attachments_path
    "/recording_studio_attachable/recordings/#{@root.id}/attachments"
  end

  def attachment_count
    @root.child_recordings.where(recordable_type: "RecordingStudioAttachable::Attachment").count
  end

  def attach_bytes(filename, bytes)
    ticket = upload_ticket(filename, bytes)
    put_upload(ticket, bytes)
    post attachments_path, params: { attachments: [{ signed_blob_id: ticket.fetch("signed_id"), name: filename }] }, as: :json
    assert_response :created, response.body
    json.fetch("attachments").first
  end

  def upload_ticket(filename, bytes)
    post recording_studio_attachable.recording_direct_uploads_path(@root),
         params: {
           blob: {
             filename: filename,
             byte_size: bytes.bytesize,
             checksum: Base64.strict_encode64(Digest::MD5.digest(bytes)),
             content_type: "image/png"
           }
         },
         as: :json
    assert_response :success, response.body
    JSON.parse(response.body)
  end

  def put_upload(ticket, bytes)
    uri = URI(ticket.dig("direct_upload", "url"))
    put "#{uri.path}?#{uri.query}", params: bytes, headers: ticket.dig("direct_upload", "headers")
    assert_response :no_content, response.body
  end

  def blob_id(ticket)
    ActiveStorage::Blob.find_signed(ticket.fetch("signed_id"), purpose: RecordingStudioAttachable::DirectUpload::PURPOSE)&.id
  end

  def uploaded(filename, bytes)
    path = Rails.root.join("tmp", filename)
    FileUtils.mkdir_p(path.dirname)
    File.binwrite(path, bytes)
    Rack::Test::UploadedFile.new(path.to_s, "image/png")
  end

  def json
    JSON.parse(response.body)
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
