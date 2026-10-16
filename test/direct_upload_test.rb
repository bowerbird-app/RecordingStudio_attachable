# frozen_string_literal: true

require "test_helper"

class DirectUploadTest < Minitest::Test
  FakeBlob = Struct.new(:content_type, :filename, :body, :metadata, :attached, keyword_init: true) do
    def attachments
      flag = attached
      relation = Object.new
      relation.define_singleton_method(:exists?) { flag }
      relation
    end

    def open
      yield StringIO.new(body)
    end
  end

  def setup
    @original = RecordingStudioAttachable.instance_variable_get(:@configuration)
    RecordingStudioAttachable.instance_variable_set(:@configuration, RecordingStudioAttachable::Configuration.new)
    ensure_blob!
  end

  def teardown
    RecordingStudioAttachable.instance_variable_set(:@configuration, @original)
  end

  def test_accept_rejects_another_actor_an_attached_blob_and_a_different_recording
    recording = recording_double("parent-1")
    actor = Struct.new(:id).new("actor-1")
    blob = issued_blob(recording, actor)

    ActiveStorage::Blob.stub(:find_signed!, blob) do
      assert_equal blob, RecordingStudioAttachable::DirectUpload.accept!("signed", recording: recording, actor: actor)

      other = Struct.new(:id).new("actor-2")
      error = assert_raises(ArgumentError) do
        RecordingStudioAttachable::DirectUpload.accept!("signed", recording: recording, actor: other)
      end
      assert_includes error.message, "actor"

      elsewhere = recording_double("parent-2")
      error = assert_raises(ArgumentError) do
        RecordingStudioAttachable::DirectUpload.accept!("signed", recording: elsewhere, actor: actor)
      end
      assert_includes error.message, "recording"

      blob.attached = true
      error = assert_raises(ArgumentError) do
        RecordingStudioAttachable::DirectUpload.accept!("signed", recording: recording, actor: actor)
      end
      assert_includes error.message, "already attached"
    end
  end

  def test_sniff_rejects_html_bytes_declared_as_png_and_accepts_a_real_png
    html = issued_blob(recording_double("parent-1"), Struct.new(:id).new("actor-1"))
    html.content_type = "image/png"
    html.filename = "photo.png"
    html.body = "<html><script>alert(1)</script></html>"
    error = assert_raises(ArgumentError) { RecordingStudioAttachable::DirectUpload.sniff!(html, {}) }
    assert_includes error.message, "does not match"

    png = issued_blob(recording_double("parent-1"), Struct.new(:id).new("actor-1"))
    png.content_type = "image/png"
    png.filename = "photo.png"
    png.body = UploadBlobBytes::PNG
    RecordingStudioAttachable::DirectUpload.sniff!(png, {})
  end

  def test_sniff_accepts_text_plain_from_the_filename_when_magic_is_absent
    blob = issued_blob(recording_double("parent-1"), Struct.new(:id).new("actor-1"))
    blob.content_type = "text/plain"
    blob.filename = "notes.txt"
    blob.body = "notes"
    RecordingStudioAttachable::DirectUpload.sniff!(blob, { allowed_content_types: ["text/plain"] })
  end

  def test_svg_is_refused_unless_the_allow_list_names_it
    assert_not RecordingStudioAttachable.configuration.allowed_content_type?("image/svg+xml")
    blob = issued_blob(recording_double("parent-1"), Struct.new(:id).new("actor-1"))
    blob.content_type = "image/svg+xml"
    blob.filename = "icon.svg"
    blob.body = %(<svg xmlns="http://www.w3.org/2000/svg"></svg>)
    error = assert_raises(ArgumentError) { RecordingStudioAttachable::DirectUpload.sniff!(blob, {}) }
    assert_includes error.message, "not allowed"
  end

  private

  def recording_double(id)
    Struct.new(:id, :recordable_type, :root_recording).new(id, "Workspace", nil)
  end

  def issued_blob(recording, actor)
    FakeBlob.new(
      content_type: "image/png",
      filename: "photo.png",
      body: UploadBlobBytes::PNG,
      metadata: RecordingStudioAttachable::DirectUpload.metadata_for(recording: recording, actor: actor),
      attached: false
    )
  end

  def ensure_blob!
    ActiveStorage.const_set(:Blob, Class.new) unless defined?(ActiveStorage::Blob)
    return if ActiveStorage::Blob.respond_to?(:find_signed!)

    ActiveStorage::Blob.define_singleton_method(:find_signed!) { |*, **| raise NotImplementedError }
  end
end
