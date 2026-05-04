# frozen_string_literal: true

require "test_helper"

class RecordAttachmentUploadTest < Minitest::Test
  FakeRecording = Struct.new(:id, :recordable_type, :root_recording, keyword_init: true)
  FakeEvent = Struct.new(:recording)
  FakeBlob = Struct.new(:content_type, :byte_size, :filename) do
    def signed_id
      "signed-id"
    end
  end
  FakeFilename = Struct.new(:value) do
    def to_s
      value
    end

    def base
      File.basename(value, File.extname(value))
    end
  end

  def setup
    @original_configuration = RecordingStudioAttachable.instance_variable_get(:@configuration)
    RecordingStudioAttachable.instance_variable_set(:@configuration, RecordingStudioAttachable::Configuration.new)
    stub_recording_studio!
    stub_accessible!
  end

  def teardown
    RecordingStudioAttachable.instance_variable_set(:@configuration, @original_configuration)
  end

  def test_creates_child_recording_with_attachment_uploaded_action
    blob = FakeBlob.new("image/png", 1024, FakeFilename.new("photo.png"))
    parent = FakeRecording.new(id: "parent-1", recordable_type: "Workspace", root_recording: FakeRecording.new(id: "root-1"))
    created_recording = Struct.new(:id, :recordable).new("child-1", Struct.new(:name, :content_type, :byte_size, :attachment_kind).new("photo", "image/png", 1024, "image"))
    event = FakeEvent.new(created_recording)

    ActiveStorage::Blob.stub(:find_signed!, blob) do
      RecordingStudio.stub(:record!, event) do
        result = RecordingStudioAttachable::Services::RecordAttachmentUpload.call(
          parent_recording: parent,
          signed_blob_id: "signed-id",
          actor: Object.new,
          name: "Upload name"
        )

        assert result.success?
        assert_equal created_recording, result.value
      end
    end
  end

  private

  def stub_recording_studio!
    return if defined?(RecordingStudio)

    Object.const_set(:RecordingStudio, Module.new)
    RecordingStudio.singleton_class.class_eval do
      define_method(:capability_options) { |_name, for_type:| {} }
    end
  end

  def stub_accessible!
    return if defined?(RecordingStudioAccessible::Authorization)

    accessible = Module.new
    accessible.singleton_class.class_eval do
      define_method(:allowed?) { |actor:, recording:, role:| actor.present? && recording.present? && role.present? }
    end
    Object.const_set(:RecordingStudioAccessible, Module.new) unless defined?(RecordingStudioAccessible)
    RecordingStudioAccessible.const_set(:Authorization, accessible)
  end
end
