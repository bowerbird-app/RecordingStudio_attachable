# frozen_string_literal: true

require "test_helper"
require_relative "../../app/queries/recording_studio_attachable/queries/for_recording"
require_relative "../../app/services/recording_studio_attachable/services/application_service"
require_relative "../../app/services/recording_studio_attachable/services/revise_attachment_metadata"
require_relative "../../app/services/recording_studio_attachable/services/revise_attachment_collection"

class ReviseAttachmentCollectionTest < Minitest::Test
  Parent = Struct.new(:id, :recordable_type) do
    attr_reader :reorders

    def initialize(id, recordable_type = "Workspace")
      super
      @reorders = []
    end
  end

  Snapshot = Struct.new(
    :id, :name, :description, :caption, :credit, :alt_text, :attachment_kind, :original_filename,
    :content_type, :byte_size, :file, keyword_init: true
  )
  Child = Struct.new(:id, :recordable_type, :parent_recording, :parent_recording_id, :recordable, :root_recording, :created_at, keyword_init: true)
  Blob = Struct.new(:metadata, :writes, keyword_init: true) do
    def update!(**kwargs)
      writes << kwargs
    end
  end
  FileDouble = Struct.new(:blob)
  Filename = Struct.new(:value) do
    def to_s
      value
    end

    def base
      "photo"
    end
  end

  def setup
    @events = []
  end

  def test_one_save_persists_every_changed_row_and_skips_the_unchanged_row
    parent = Parent.new("parent-1")
    changed = attachment_recording("image-1", parent, caption: "Old")
    same = attachment_recording("image-2", parent, caption: "Same")
    token = editor_token(parent, [changed, same])

    save_collection(parent, [changed, same], token, [
                      { recording_id: "image-1", caption: "Pier light" },
                      { recording_id: "image-2", caption: "Same" }
                    ])

    assert_equal [["image-1", "Pier light"]], recorded_captions
    assert_equal "attachment_metadata_revised", @events.first[:action]
    assert_empty parent.reorders
  end

  def test_editing_one_caption_leaves_the_other_snapshot_and_the_blob
    parent = Parent.new("parent-1")
    blob = Blob.new(metadata: { "alt" => "blob alt" }, writes: [])
    left = attachment_recording("image-1", parent, caption: "Left", blob: blob)
    right = attachment_recording("image-2", parent, caption: "Right", blob: blob)
    token = editor_token(parent, [left, right], fields: [:caption])

    save_collection(parent, [left, right], token, [
                      { recording_id: "image-1", caption: "Pier light" },
                      { recording_id: "image-2", caption: "Right" }
                    ])

    assert_equal [["image-1", "Pier light"]], recorded_captions
    assert_equal "Right", right.recordable.caption
    assert_equal({ "alt" => "blob alt" }, blob.metadata)
    assert_empty blob.writes
    assert_same blob, left.recordable.file.blob
    assert_same blob, right.recordable.file.blob
  end

  def test_sortable_parent_reorders_with_the_spliced_id_list
    file_a = attachment_recording("file-a", nil, kind: "file")
    image_1 = attachment_recording("image-1", nil, caption: "One")
    file_b = attachment_recording("file-b", nil, kind: "file")
    image_2 = attachment_recording("image-2", nil, caption: "Two")
    parent = orderable_parent([file_a, image_1, file_b, image_2])
    [image_1, image_2].each { |image| image.parent_recording = parent }
    token = editor_token(parent, [image_1, image_2], sortable: true)

    save_collection(parent, [image_1, image_2], token, [
                      { recording_id: "image-2", order: "1", caption: "Two" },
                      { recording_id: "image-1", order: "2", caption: "One" }
                    ])

    assert_empty @events
    assert_equal([%w[file-a image-2 file-b image-1]], parent.reorders.map { |call| call[:ordered_recording_ids] })
    assert_equal :actor, parent.reorders.first[:actor]
  end

  def test_sortable_token_on_a_parent_without_reorder_does_not_reorder
    orderable = orderable_parent([])
    token = editor_token(orderable, [], sortable: true)
    plain = Parent.new("parent-1")

    result = RecordingStudioAttachable::Authorization.stub(:authorize!, true) do
      RecordingStudioAttachable::Services::ReviseAttachmentCollection.call(
        recording: plain,
        params: { signed_editor: token, rows: [] },
        actor: :actor
      )
    end

    assert result.failure?
    assert_equal(
      "sortable: true needs the parent to respond to recording_studio_orderable_reorder!. This parent does not.",
      result.error
    )
  end

  def test_sortable_false_does_not_reorder_when_the_parent_can
    parent = orderable_parent([])
    image = attachment_recording("image-1", parent, caption: "Old")
    parent.define_singleton_method(:recording_studio_orderable_children) { [image] }
    token = editor_token(parent, [image], sortable: false)

    save_collection(parent, [image], token, [{ recording_id: "image-1", order: "9", caption: "Pier light" }])

    assert_equal [["image-1", "Pier light"]], recorded_captions
    assert_empty parent.reorders
  end

  def test_second_identical_save_adds_no_snapshot_and_no_reorder
    image_1 = attachment_recording("image-1", nil, caption: "One")
    image_2 = attachment_recording("image-2", nil, caption: "Two")
    parent = orderable_parent([image_1, image_2])
    [image_1, image_2].each { |image| image.parent_recording = parent }
    token = editor_token(parent, [image_1, image_2], sortable: true)

    save_collection(parent, [image_1, image_2], token, [
                      { recording_id: "image-1", order: "1", caption: "One" },
                      { recording_id: "image-2", order: "2", caption: "Two" }
                    ])

    assert_empty @events
    assert_empty parent.reorders
  end

  def test_row_missing_from_orderable_children_does_not_reorder
    image = attachment_recording("image-1", nil, caption: "Old")
    parent = orderable_parent([])
    image.parent_recording = parent
    token = editor_token(orderable_parent([image]), [image], sortable: true)

    result = nil
    with_membership([image]) do
      RecordingStudioAttachable::Authorization.stub(:authorize!, true) do
        RecordingStudio.stub(:record!, ->(**) { raise "should not record" }) do
          result = RecordingStudioAttachable::Services::ReviseAttachmentCollection.call(
            recording: parent,
            params: { signed_editor: token, rows: [{ recording_id: "image-1", order: "1", caption: "Pier light" }] },
            actor: :actor
          )
        end
      end
    end

    assert result.failure?
    assert_equal(
      "The parent must allow RecordingStudioAttachable::Attachment in Orderable allows, or omit allows.",
      result.error
    )
    assert_empty parent.reorders
  end

  private

  def recorded_captions
    @events.map { |event| [event[:recording].id, event[:recordable].caption] }
  end

  def save_collection(parent, recordings, token, rows)
    with_membership(recordings) do
      RecordingStudioAttachable::Authorization.stub(:authorize!, true) do
        ensure_attachment_class!
        RecordingStudioAttachable::Attachment.stub(:build_from_blob, method(:built_snapshot)) do
          RecordingStudio.stub(:record!, method(:capture_event)) do
            result = RecordingStudioAttachable::Services::ReviseAttachmentCollection.call(
              recording: parent,
              params: { signed_editor: token, rows: rows },
              actor: :actor
            )
            assert result.success?, result.error
          end
        end
      end
    end
  end

  def editor_token(parent, recordings, fields: [:caption], sortable: false)
    with_membership(recordings) do
      RecordingStudioAttachable::AttachmentCollection.for(
        recording: parent,
        association: :images,
        fields: fields,
        sortable: sortable
      ).signed_editor
    end
  end

  def with_membership(recordings, &)
    query = Object.new
    query.define_singleton_method(:unpaged) { recordings }
    RecordingStudioAttachable::Queries::ForRecording.stub(:new, ->(**) { query }, &)
  end

  def orderable_parent(children)
    parent = Parent.new("parent-1")
    parent.define_singleton_method(:recording_studio_orderable_children) { children }
    parent.define_singleton_method(:recording_studio_orderable_reorder!) do |**kwargs|
      reorders << kwargs
    end
    parent
  end

  def attachment_recording(id, parent, caption: nil, blob: nil, kind: "image")
    file_blob = blob || Blob.new(metadata: {}, writes: [])
    Child.new(
      id: id,
      recordable_type: "RecordingStudioAttachable::Attachment",
      parent_recording: parent,
      parent_recording_id: parent&.id,
      created_at: Time.utc(2026, 1, 1),
      root_recording: Parent.new("root-1"),
      recordable: Snapshot.new(
        id: "recordable-#{id}",
        name: id,
        description: nil,
        caption: caption,
        credit: nil,
        alt_text: nil,
        attachment_kind: kind,
        original_filename: "#{id}.png",
        content_type: "image/png",
        byte_size: 12,
        file: FileDouble.new(file_blob)
      )
    )
  end

  def built_snapshot(**kwargs)
    Snapshot.new(
      id: "snapshot",
      name: kwargs[:name],
      description: kwargs[:description],
      caption: kwargs[:caption],
      credit: kwargs[:credit],
      alt_text: kwargs[:alt_text],
      attachment_kind: "image",
      original_filename: "photo.png",
      content_type: "image/png",
      byte_size: 12,
      file: nil
    )
  end

  def capture_event(**kwargs)
    @events << kwargs
    Struct.new(:recording).new(kwargs[:recording])
  end

  def ensure_attachment_class!
    klass =
      if RecordingStudioAttachable.const_defined?(:Attachment, false)
        RecordingStudioAttachable::Attachment
      else
        RecordingStudioAttachable.const_set(:Attachment, Class.new)
      end
    return if klass.respond_to?(:build_from_blob)

    klass.define_singleton_method(:build_from_blob) { |**| raise NotImplementedError }
  end
end
