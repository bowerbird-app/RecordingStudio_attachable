# frozen_string_literal: true

require "test_helper"
require_relative "../../app/services/recording_studio_attachable/services/application_service"
require_relative "../../app/services/recording_studio_attachable/services/record_attachment_upload"

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
    stub_active_storage!
    stub_attachment_class!
  end

  def teardown
    RecordingStudioAttachable.instance_variable_set(:@configuration, @original_configuration)
  end

  def test_creates_child_recording_with_attachment_uploaded_action
    blob = FakeBlob.new("image/png", 1024, FakeFilename.new("photo.png"))
    parent = FakeRecording.new(id: "parent-1", recordable_type: "Workspace", root_recording: FakeRecording.new(id: "root-1"))
    built_attachment = Struct.new(:id, :name, :content_type, :byte_size, :attachment_kind, :original_filename).new(
      "attachment-1", "Upload name", "image/png", 1024, "image", "photo.png"
    )
    recordable = Struct.new(:name, :content_type, :byte_size, :attachment_kind).new("photo", "image/png", 1024, "image")
    created_recording = Struct.new(:id, :recordable).new("child-1", recordable)
    event = FakeEvent.new(created_recording)

    ActiveStorage::Blob.stub(:find_signed!, blob) do
      RecordingStudioAttachable::Attachment.stub(:build_from_blob, built_attachment) do
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
  end

  private

  def stub_recording_studio!
    studio = defined?(RecordingStudio) ? RecordingStudio : Object.const_set(:RecordingStudio, Module.new)
    studio.singleton_class.class_eval do
      define_method(:capability_options) { |_name, _for_type: nil, **| {} } unless method_defined?(:capability_options)
      define_method(:record!) { |**| raise NotImplementedError } unless method_defined?(:record!)
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

  def stub_active_storage!
    return if defined?(ActiveStorage::Blob)

    blob_class = Class.new do
      class << self
        def find_signed!(*)
          raise NotImplementedError
        end
      end
    end

    Object.const_set(:ActiveStorage, Module.new) unless defined?(ActiveStorage)
    ActiveStorage.const_set(:Blob, blob_class)
  end

  def stub_attachment_class!
    return if defined?(RecordingStudioAttachable::Attachment)

    klass = Class.new do
      def self.build_from_blob(*)
        raise NotImplementedError
      end
    end
    RecordingStudioAttachable.const_set(:Attachment, klass)
  end
end
