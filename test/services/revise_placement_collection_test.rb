# frozen_string_literal: true

require "test_helper"
require_relative "../../app/services/recording_studio_attachable/services/application_service"
require_relative "../../app/services/recording_studio_attachable/services/revise_attachment_metadata"
require_relative "../../app/services/recording_studio_attachable/services/revise_placement_collection"

class RevisePlacementCollectionTest < Minitest::Test
  Parent = Struct.new(:id, :recordable_type)
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

  def setup
    @events = []
    @reorders = []
  end

  def test_saves_caption_credit_and_alt_then_reorders_through_library
    parent = orderable_parent
    first = attachment_recording("image-1", parent, caption: "Old", credit: "Ada", alt_text: "Alt")
    second = attachment_recording("image-2", parent, caption: "Two")
    left = placement_recording("place-1", parent, first)
    right = placement_recording("place-2", parent, second)
    token = editor_token(parent, [left, right], [first, second])

    result = save_collection(parent, [left, right], [first, second], token, [
                               { recording_id: "place-2", order: "1", caption: "Two", credit: "", alt_text: "" },
                               { recording_id: "place-1", order: "2", caption: "Kiln light", credit: "Bea", alt_text: "Canister" }
                             ])

    assert result.success?, result.error
    assert_equal [["image-1", "Kiln light", "Bea", "Canister"]], recorded_fields
    assert_equal [%w[place-2 place-1]], @reorders
  end

  def test_skips_reorder_when_order_is_unchanged
    parent = orderable_parent
    photo = attachment_recording("image-1", parent, caption: "Old")
    placement = placement_recording("place-1", parent, photo)
    token = editor_token(parent, [placement], [photo])

    result = save_collection(parent, [placement], [photo], token, [
                               { recording_id: "place-1", order: "1", caption: "Pier light", credit: "", alt_text: "" }
                             ])

    assert result.success?, result.error
    assert_equal [["image-1", "Pier light", nil, nil]], recorded_fields
    assert_empty @reorders
  end

  private

  def recorded_fields
    @events.map { |event| [event[:recording].id, event[:recordable].caption, event[:recordable].credit, event[:recordable].alt_text] }
  end

  def save_collection(parent, placements, photos, token, rows)
    with_membership(placements, photos) do
      RecordingStudioAttachable::Authorization.stub(:authorize_placement!, true) do
        RecordingStudioAttachable::Authorization.stub(:authorize!, true) do
          ensure_attachment_class!
          RecordingStudioAttachable::Attachment.stub(:build_from_blob, method(:built_snapshot)) do
            RecordingStudio.stub(:record!, method(:capture_event)) do
              RecordingStudioLibrary.stub(:reorder!, lambda { |holder, ids, actor:|
                @reorders << ids.map(&:to_s)
                holder
              }) do
                RecordingStudioAttachable::Services::RevisePlacementCollection.call(
                  recording: parent,
                  params: { signed_editor: token, rows: rows },
                  actor: :actor
                )
              end
            end
          end
        end
      end
    end
  end

  def editor_token(parent, placements, photos)
    with_membership(placements, photos) do
      RecordingStudioAttachable::AttachmentCollection.for(
        recording: parent,
        association: :placements,
        fields: %i[caption credit alt_text],
        sortable: true
      ).signed_editor
    end
  end

  def with_membership(placements, photos, &)
    resolved = placements.each_with_index.map do |placement, index|
      photo = photos[index]
      RecordingStudioAttachable::Placements::Resolved.new(
        placement_recording: placement,
        attachment_recording: photo,
        attachment: photo.recordable
      )
    end
    RecordingStudioAttachable::Placements.stub(:resolve, resolved, &)
  end

  def orderable_parent
    parent = Parent.new("parent-1", "Gallery")
    parent.define_singleton_method(:recording_studio_orderable_children) { @orderable_children || [] }
    parent.define_singleton_method(:recording_studio_orderable_children=) { |value| @orderable_children = value }
    parent.define_singleton_method(:recording_studio_orderable_reorder!) { |**| nil }
    parent
  end

  def attachment_recording(id, parent, caption: nil, credit: nil, alt_text: nil)
    Child.new(
      id: id,
      recordable_type: "RecordingStudioAttachable::Attachment",
      parent_recording: parent,
      parent_recording_id: parent&.id,
      created_at: Time.utc(2026, 1, 1),
      root_recording: Parent.new("root-1", "Workspace"),
      recordable: Snapshot.new(
        id: "recordable-#{id}",
        name: id,
        description: nil,
        caption: caption,
        credit: credit,
        alt_text: alt_text,
        attachment_kind: "image",
        original_filename: "#{id}.png",
        content_type: "image/png",
        byte_size: 12,
        file: FileDouble.new(Blob.new(metadata: {}, writes: []))
      )
    )
  end

  def placement_recording(id, parent, photo)
    placement = Child.new(
      id: id,
      recordable_type: "RecordingStudioLibrary::Placement",
      parent_recording: parent,
      parent_recording_id: parent.id,
      created_at: Time.utc(2026, 1, 1),
      recordable: photo.recordable
    )
    children = Array(parent.recording_studio_orderable_children) + [placement]
    parent.recording_studio_orderable_children = children
    placement
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
