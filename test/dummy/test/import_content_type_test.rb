# frozen_string_literal: true

require "test_helper"
require "stringio"

class ImportContentTypeTest < ActiveSupport::TestCase
  SVG = '<svg xmlns="http://www.w3.org/2000/svg"></svg>'
  PDF = "%PDF-1.4\n1 0 obj<<>>endobj\ntrailer<<>>\n%%EOF\n"

  setup do
    @previous_actor = Current.actor
    @owner = User.create!(
      email: "import-#{SecureRandom.hex(4)}@example.com",
      password: "Password123!",
      password_confirmation: "Password123!",
      name: "Importer"
    )
    Current.actor = @owner
    workspace = Workspace.create!(name: "Import types #{SecureRandom.hex(4)}")
    @root = RecordingStudio.create_root_recording!(workspace, actor: @owner)
    @page = @root.record(Page, actor: @owner) { |page| page.title = "Notes" }
    authorizer = RecordingStudioAccessible.configuration.access_management_authorizer
    RecordingStudioAccessible.configuration.access_management_authorizer = ->(**) { true }
    result = RecordingStudioAccessible.bootstrap_owner_access!(recording: @root, actor: @owner)
    raise result.error if result.failure?
  ensure
    RecordingStudioAccessible.configuration.access_management_authorizer = authorizer
  end

  teardown do
    Current.actor = @previous_actor
  end

  test "a pdf served as octet-stream follows the parent allow list" do
    accepted = import(@root, PDF, "notes.pdf", "application/octet-stream")
    assert accepted.success?, accepted.error.to_s
    assert_equal "application/pdf", accepted.value.recordable.content_type

    refused = import(@page, PDF, "notes.pdf", "application/octet-stream")
    assert refused.failure?
    assert_includes refused.error, "is not allowed"
  end

  test "an svg labelled as an image or octet-stream is refused under image/*" do
    labelled = import(@root, SVG, "mark.svg", "image/png")
    generic = import(@root, SVG, "mark.svg", "application/octet-stream")

    assert labelled.failure?
    assert generic.failure?
    assert_includes labelled.error, "is not allowed"
    assert_includes generic.error, "is not allowed"
  end

  test "a mislabelled disallowed type is refused" do
    result = import(@page, PDF, "notes.png", "image/png")

    assert result.failure?
    assert_includes result.error, "is not allowed"
  end

  test "a provider import uses the bytes when the declared type is generic or wrong" do
    accepted = RecordingStudioAttachable::Services::ImportRemoteFiles.call(
      parent_recording: @root,
      provider_key: "demo",
      actor: @owner,
      payloads: [payload(PDF, "notes.pdf", "application/octet-stream")]
    )
    refused = RecordingStudioAttachable::Services::ImportRemoteFiles.call(
      parent_recording: @root,
      provider_key: "demo",
      actor: @owner,
      payloads: [payload(SVG, "mark.svg", "image/png")]
    )

    assert accepted.success?, accepted.error.to_s
    assert_equal "application/pdf", accepted.value.first.recordable.content_type
    assert refused.failure?
    assert_includes refused.error, "is not allowed"
  end

  private

  def import(parent, bytes, filename, content_type)
    RecordingStudioAttachable::Services::ImportAttachment.call(
      parent_recording: parent,
      io: StringIO.new(bytes),
      filename: filename,
      content_type: content_type,
      actor: @owner
    )
  end

  def payload(bytes, filename, content_type)
    {
      download: -> { { io: StringIO.new(bytes), filename: filename, content_type: content_type } },
      filename: filename,
      content_type: content_type
    }
  end
end
