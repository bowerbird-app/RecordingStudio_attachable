# frozen_string_literal: true

require "test_helper"
require_relative "../../app/services/recording_studio_attachable/services/application_service"
require_relative "../../app/services/recording_studio_attachable/services/import_attachments"
require_relative "../../app/services/recording_studio_attachable/services/record_attachment_upload"
require_relative "../../app/services/recording_studio_attachable/services/import_remote_files"

class ImportRemoteFilesTest < Minitest::Test
  FakeRecording = Struct.new(:id, :recordable_type, :root_recording, keyword_init: true)
  Actor = Struct.new(:id)
  Imported = Struct.new(:id, :name, :content_type, :byte_size, :attachment_kind, :original_filename, keyword_init: true)

  def test_downloads_payloads_stamps_provider_and_closes_io
    parent = FakeRecording.new(id: "parent-1")
    io = StringIO.new("bytes")
    captured = nil
    result = RecordingStudioAttachable::Services::BaseService::Result.new(success: true, value: [:ok])

    RecordingStudioAttachable::Services::ImportAttachments.stub(:call, lambda { |**kwargs|
      captured = kwargs
      result
    }) do
      returned = RecordingStudioAttachable::Services::ImportRemoteFiles.call(
        parent_recording: parent,
        provider_key: :my_cloud,
        actor: :actor,
        impersonator: :impersonator,
        payloads: [
          {
            download: -> { { io: io, filename: "brief.png", content_type: "image/png" } },
            filename: "brief.png",
            content_type: "image/png",
            byte_size: 5,
            name: "Brief",
            metadata: { external_id: "file-1", external_url: "https://cloud.test/file-1", extra: "kept" }
          }
        ]
      )

      assert returned.success?
    end

    attachment = captured[:attachments].first
    assert_same parent, captured[:parent_recording]
    assert_equal "my_cloud", captured[:source]
    assert_equal "brief.png", attachment[:filename]
    assert_equal "Brief", attachment[:name]
    assert_equal "file-1", attachment[:metadata][:external_id]
    assert_equal "my_cloud", attachment[:metadata][:provider]
    assert_equal "kept", attachment[:metadata][:extra]
    assert io.closed?
  end

  def test_rejects_oversized_declared_byte_size
    parent = FakeRecording.new(id: "parent-1")
    original_max = RecordingStudioAttachable.configuration.max_file_size
    RecordingStudioAttachable.configuration.max_file_size = 4

    result = RecordingStudioAttachable::Services::ImportRemoteFiles.call(
      parent_recording: parent,
      provider_key: :my_cloud,
      payloads: [{ io: StringIO.new("bytes"), filename: "too-big.bin", byte_size: 5 }]
    )

    refute result.success?
    assert_equal "Remote file exceeds maximum file size", result.error
  ensure
    RecordingStudioAttachable.configuration.max_file_size = original_max
  end

  def test_a_string_io_download_imports
    io = StringIO.new(UploadBlobBytes::PNG)
    result = import_download([{ download: -> { io }, filename: "brief.png", content_type: "image/png" }])

    assert result.success?
    assert_equal "brief.png", @uploaded_filename
    assert_equal "image/png", @uploaded_type
    assert_equal UploadBlobBytes::PNG, @uploaded_bytes
    assert io.closed?
  end

  def test_a_hash_download_imports
    io = StringIO.new(UploadBlobBytes::PNG)
    payload = {
      download: -> { { io: io, filename: "brief.png", content_type: "image/png" } },
      filename: "fallback.png",
      content_type: "application/octet-stream"
    }
    result = import_download([payload])

    assert result.success?
    assert_equal "brief.png", @uploaded_filename
    assert_equal "image/png", @uploaded_type
    assert_equal UploadBlobBytes::PNG, @uploaded_bytes
    assert io.closed?
  end

  def test_an_oversized_string_io_is_denied
    original_max = RecordingStudioAttachable.configuration.max_file_size
    RecordingStudioAttachable.configuration.max_file_size = 4

    result = RecordingStudioAttachable::Services::ImportRemoteFiles.call(
      parent_recording: workspace,
      provider_key: :my_cloud,
      payloads: [{ download: -> { StringIO.new("12345") }, filename: "too-big.bin", content_type: "application/octet-stream" }]
    )

    refute result.success?
    assert_equal "Remote file exceeds maximum file size", result.error
  ensure
    RecordingStudioAttachable.configuration.max_file_size = original_max
  end

  def test_a_string_io_over_the_recordable_file_size_cap_is_denied
    result = import_download(
      [{ download: -> { StringIO.new("12345") }, filename: "too-big.png", content_type: "image/png" }],
      capability_options: { max_file_size: 4 }
    )

    refute result.success?
    assert_includes result.error, "Blob exceeds maximum file size"
  end

  def test_a_string_io_batch_over_the_file_count_is_denied
    original_count = RecordingStudioAttachable.configuration.max_file_count
    RecordingStudioAttachable.configuration.max_file_count = 1

    result = RecordingStudioAttachable::Services::ImportRemoteFiles.call(
      parent_recording: workspace,
      provider_key: :my_cloud,
      payloads: [
        { download: -> { StringIO.new("a") }, filename: "a.txt", content_type: "text/plain" },
        { download: -> { StringIO.new("b") }, filename: "b.txt", content_type: "text/plain" }
      ]
    )

    refute result.success?
    assert_equal "You can import up to 1 file at a time", result.error
  ensure
    RecordingStudioAttachable.configuration.max_file_count = original_count
  end

  def test_a_string_io_whose_bytes_do_not_match_the_declared_type_is_denied
    png_payload = {
      download: -> { StringIO.new("<html>not a png</html>") },
      filename: "photo.png",
      content_type: "image/png"
    }
    svg_payload = {
      download: -> { StringIO.new(%(<svg xmlns="http://www.w3.org/2000/svg"></svg>)) },
      filename: "icon.svg",
      content_type: "image/svg+xml"
    }
    png_declared = import_download([png_payload])
    svg_declared = import_download([svg_payload])

    refute png_declared.success?
    assert_includes png_declared.error, "does not match"
    refute svg_declared.success?
    assert_includes svg_declared.error, "image/svg+xml"
    assert_includes svg_declared.error, "not allowed"
  end

  def test_an_unexpected_download_returns_a_clear_error
    array_download = RecordingStudioAttachable::Services::ImportRemoteFiles.call(
      parent_recording: workspace,
      provider_key: :my_cloud,
      payloads: [{ download: -> { ["nope"] }, filename: "nope.txt" }]
    )
    string_download = RecordingStudioAttachable::Services::ImportRemoteFiles.call(
      parent_recording: workspace,
      provider_key: :my_cloud,
      payloads: [{ download: -> { "nope" }, filename: "nope.txt" }]
    )

    refute array_download.success?
    assert_equal "download must return io: or an IO", array_download.error
    refute string_download.success?
    assert_equal "download must return io: or an IO", string_download.error
  end

  private

  def workspace
    root = FakeRecording.new(id: "root-1", recordable_type: "Workspace")
    FakeRecording.new(id: "parent-1", recordable_type: "Workspace", root_recording: root)
  end

  def import_download(payloads, capability_options: nil)
    recording = Imported.new(
      id: "attachment-1",
      name: "brief",
      content_type: "image/png",
      byte_size: 1,
      attachment_kind: "image",
      original_filename: payloads.first[:filename]
    )
    result = nil
    event = Struct.new(:recording).new(recording)
    previous_authorizer = RecordingStudioAttachable.configuration.authorize_with
    RecordingStudioAttachable.configuration.authorize_with = ->(**) { true }
    ensure_blob_class!
    ensure_attachment_class!
    ensure_singleton_method(ActiveStorage::Blob, :create_and_upload!)
    ensure_singleton_method(ActiveStorage::Blob, :find_signed!)
    ensure_singleton_method(RecordingStudioAttachable::Attachment, :build_from_blob)

    RecordingStudio.configuration.stub(:capability_enabled?, true) do
      with_capability_options(capability_options) do
        ActiveStorage::Blob.stub(:create_and_upload!, lambda { |**kwargs|
          @uploaded_bytes = kwargs.fetch(:io).read
          kwargs.fetch(:io).rewind
          @uploaded_type = kwargs[:content_type]
          @uploaded_filename = kwargs[:filename]
          memory_blob(kwargs)
        }) do
          ActiveStorage::Blob.stub(:find_signed!, ->(*, **) { @memory_blob }) do
            RecordingStudioAttachable::Attachment.stub(:build_from_blob, recording) do
              RecordingStudio.stub(:record!, event) do
                result = RecordingStudioAttachable::Services::ImportRemoteFiles.call(
                  parent_recording: workspace,
                  provider_key: :my_cloud,
                  actor: Actor.new("actor-1"),
                  payloads: payloads
                )
              end
            end
          end
        end
      end
    end
    result
  ensure
    RecordingStudioAttachable.configuration.authorize_with = previous_authorizer
    remove_attachment_class!
  end

  def with_capability_options(options, &block)
    return block.call if options.nil?

    RecordingStudio.stub(:capability_options, options, &block)
  end

  def memory_blob(kwargs)
    @memory_blob = MemoryBlob.new(
      bytes: @uploaded_bytes,
      content_type: kwargs[:content_type],
      filename: kwargs[:filename].to_s,
      metadata: kwargs[:metadata] || {}
    )
  end

  def ensure_singleton_method(object, name)
    return if object.respond_to?(name)

    object.define_singleton_method(name) { |*, **| raise NotImplementedError, name.to_s }
  end

  def ensure_blob_class!
    Object.const_set(:ActiveStorage, Module.new) unless defined?(ActiveStorage)
    return if defined?(ActiveStorage::Blob)

    ActiveStorage.const_set(:Blob, Class.new)
    @created_blob_class = true
  end

  def ensure_attachment_class!
    return if defined?(RecordingStudioAttachable::Attachment)

    RecordingStudioAttachable.const_set(:Attachment, Class.new)
    @created_attachment_class = true
  end

  def remove_attachment_class!
    return unless @created_attachment_class

    RecordingStudioAttachable.send(:remove_const, :Attachment)
    @created_attachment_class = false
  end

  class MemoryBlob
    attr_reader :content_type, :byte_size, :metadata, :filename, :id

    def initialize(bytes:, content_type:, filename:, metadata:)
      @bytes = bytes
      @content_type = content_type
      @filename = filename
      @metadata = metadata
      @byte_size = bytes.bytesize
      @id = "blob-1"
    end

    def signed_id(**)
      "signed-blob"
    end

    def open
      yield StringIO.new(@bytes)
    end

    def attachments
      []
    end

    def purge; end

    def persisted?
      true
    end
  end
end
