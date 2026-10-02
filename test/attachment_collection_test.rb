# frozen_string_literal: true

require "test_helper"
require_relative "../app/queries/recording_studio_attachable/queries/for_recording"

class AttachmentCollectionTest < Minitest::Test
  Parent = Struct.new(:id) do
    def position
      raise "position column"
    end
  end

  Snapshot = Struct.new(:name, :description, :caption, :credit, :alt_text, :original_filename, keyword_init: true)
  Child = Struct.new(:id, :created_at, :recordable, keyword_init: true)

  def test_rows_follow_direct_unpaged_membership
    older = child("older", created_at: Time.utc(2026, 1, 1))
    newer = child("newer", created_at: Time.utc(2026, 2, 1))
    parent = Parent.new("parent-1")

    collection = with_membership([older, newer]) do
      RecordingStudioAttachable::AttachmentCollection.for(
        recording: parent,
        association: :images,
        fields: [:caption],
        sortable: false
      )
    end

    assert_equal(%w[newer older], collection.rows.map { |row| row.recording.id })
    assert_equal "parent-1", @query_kwargs[:recording].id
    assert_equal :direct, @query_kwargs[:scope]
    assert_equal false, @query_kwargs[:include_trashed]
    assert_equal :images, @query_kwargs[:kind]
    assert_equal 2, collection.rows.size
  end

  def test_unpaged_membership_returns_every_child
    children = Array.new(30) { |index| child("image-#{index}", created_at: Time.utc(2026, 1, 1) + index) }
    collection = with_membership(children) do
      RecordingStudioAttachable::AttachmentCollection.for(
        recording: Parent.new("parent-1"),
        association: :files,
        fields: [:name],
        sortable: false
      )
    end

    assert_equal 30, collection.rows.size
    assert_equal :files, @query_kwargs[:kind]
    assert_equal "image-29", collection.rows.first.recording.id
  end

  def test_requested_fields_omit_alt_text_and_ignore_a_posted_alt_text
    image = child("image-1", caption: "Pier", alt_text: "Old alt")
    collection = with_membership([image]) do
      RecordingStudioAttachable::AttachmentCollection.for(
        recording: Parent.new("parent-1"),
        association: :images,
        fields: %i[caption credit],
        sortable: false
      )
    end

    assert_equal %w[Caption Credit], collection.fields.map(&:label)
    refute_includes collection.fields.map(&:key), :alt_text

    saved = with_membership([image]) do
      RecordingStudioAttachable::AttachmentCollection.from_params(
        recording: Parent.new("parent-1"),
        params: {
          signed_editor: collection.signed_editor,
          rows: [{ recording_id: "image-1", caption: "Pier", alt_text: "Sneaky", credit: "" }]
        }
      )
    end

    assert_empty saved.revisions
  end

  def test_title_and_unknown_association_and_empty_fields_raise
    parent = Parent.new("parent-1")

    title_error = assert_raises(ArgumentError) do
      RecordingStudioAttachable::AttachmentCollection.for(
        recording: parent, association: :images, fields: [:title], sortable: false
      )
    end
    association_error = assert_raises(ArgumentError) do
      RecordingStudioAttachable::AttachmentCollection.for(
        recording: parent, association: :photos, fields: [:caption], sortable: false
      )
    end
    empty_error = assert_raises(ArgumentError) do
      RecordingStudioAttachable::AttachmentCollection.for(
        recording: parent, association: :images, fields: [], sortable: false
      )
    end

    assert_equal "Unknown field: title", title_error.message
    assert_equal "Unknown association: photos", association_error.message
    assert_equal "fields must be present", empty_error.message
  end

  def test_preview_defaults_to_square_and_natural_uses_med
    parent = Parent.new("parent-1")
    square = with_membership([]) do
      RecordingStudioAttachable::AttachmentCollection.for(
        recording: parent, association: :images, fields: [:caption], sortable: false
      )
    end
    natural = with_membership([]) do
      RecordingStudioAttachable::AttachmentCollection.for(
        recording: parent, association: :images, fields: [:caption], sortable: false, preview: "natural"
      )
    end
    reloaded = with_membership([]) do
      RecordingStudioAttachable::AttachmentCollection.from_params(
        recording: parent,
        params: { signed_editor: natural.signed_editor, rows: [] }
      )
    end

    assert_equal :square, square.preview
    assert_equal :square_med, square.preview_variant
    assert_predicate square, :square_preview?
    assert_equal :natural, natural.preview
    assert_equal :med, natural.preview_variant
    refute_predicate natural, :square_preview?
    assert_equal :square, reloaded.preview
  end

  def test_unknown_preview_raises
    parent = Parent.new("parent-1")
    crop = assert_raises(ArgumentError) do
      RecordingStudioAttachable::AttachmentCollection.for(
        recording: parent, association: :images, fields: [:caption], sortable: false, preview: :crop
      )
    end
    blank = assert_raises(ArgumentError) do
      RecordingStudioAttachable::AttachmentCollection.for(
        recording: parent, association: :images, fields: [:caption], sortable: false, preview: nil
      )
    end

    assert_equal "Unknown preview: :crop. Use :square or :natural.", crop.message
    assert_equal "Unknown preview: nil. Use :square or :natural.", blank.message
  end

  def test_sortable_without_reorder_raises_and_does_not_sort_by_created_at
    parent = Parent.new("parent-1")
    error = assert_raises(ArgumentError) do
      with_membership([child("newer", created_at: Time.utc(2026, 2, 1))]) do
        RecordingStudioAttachable::AttachmentCollection.for(
          recording: parent, association: :images, fields: [:caption], sortable: true
        )
      end
    end

    assert_equal(
      "sortable: true needs the parent to respond to recording_studio_orderable_reorder!. This parent does not.",
      error.message
    )
  end

  def test_sortable_false_stays_newest_first_when_the_parent_can_reorder
    older = child("older", created_at: Time.utc(2026, 1, 1))
    newer = child("newer", created_at: Time.utc(2026, 2, 1))
    parent = orderable_parent([older, newer])

    collection = with_membership([older, newer]) do
      RecordingStudioAttachable::AttachmentCollection.for(
        recording: parent, association: :images, fields: [:caption], sortable: false
      )
    end

    assert_equal(%w[newer older], collection.rows.map { |row| row.recording.id })
  end

  def test_sortable_display_follows_orderable_children
    older = child("image-1", created_at: Time.utc(2026, 1, 1))
    newer = child("image-2", created_at: Time.utc(2026, 3, 1))
    parent = orderable_parent([newer, older])

    collection = with_membership([older, newer]) do
      RecordingStudioAttachable::AttachmentCollection.for(
        recording: parent, association: :images, fields: [:caption], sortable: true
      )
    end

    assert_equal(%w[image-2 image-1], collection.rows.map { |row| row.recording.id })
    assert_equal [1, 2], collection.rows.map(&:order)
  end

  def test_sortable_row_missing_from_orderable_children_raises
    image = child("image-1")
    parent = orderable_parent([])
    error = assert_raises(ArgumentError) do
      with_membership([image]) do
        RecordingStudioAttachable::AttachmentCollection.for(
          recording: parent, association: :images, fields: [:caption], sortable: true
        )
      end
    end

    assert_equal(
      "The parent must allow RecordingStudioAttachable::Attachment in Orderable allows, or omit allows.",
      error.message
    )
  end

  def test_revisions_skip_unchanged_rows_blank_name_and_unsigned_keys
    image = child("image-1", name: "Pier", caption: "Hello", description: "Notes")
    parent = Parent.new("parent-1")
    collection = with_membership([image]) do
      RecordingStudioAttachable::AttachmentCollection.for(
        recording: parent,
        association: :images,
        fields: %i[caption name description],
        sortable: false
      )
    end

    saved = with_membership([image]) do
      RecordingStudioAttachable::AttachmentCollection.from_params(
        recording: parent,
        params: {
          signed_editor: collection.signed_editor,
          rows: [{
            recording_id: "image-1",
            caption: "",
            name: "",
            description: "Notes",
            alt_text: "Sneaky"
          }]
        }
      )
    end

    assert_equal [{ caption: "" }], saved.revisions.map(&:changes)
    assert_equal "image-1", saved.revisions.first.recording.id
  end

  def test_recording_outside_the_association_raises
    image = child("image-1", caption: "Hello")
    parent = Parent.new("parent-1")
    collection = with_membership([image]) do
      RecordingStudioAttachable::AttachmentCollection.for(
        recording: parent, association: :images, fields: [:caption], sortable: false
      )
    end

    error = assert_raises(ArgumentError) do
      with_membership([image]) do
        RecordingStudioAttachable::AttachmentCollection.from_params(
          recording: parent,
          params: {
            signed_editor: collection.signed_editor,
            rows: [{ recording_id: "gone", caption: "Nope" }]
          }
        )
      end
    end

    assert_equal "One of these is gone. Reload the page and try again.", error.message
  end

  def test_tampered_token_and_a_token_for_another_parent_raise
    image = child("image-1")
    parent = Parent.new("parent-1")
    collection = with_membership([image]) do
      RecordingStudioAttachable::AttachmentCollection.for(
        recording: parent, association: :images, fields: [:caption], sortable: false
      )
    end
    tampered = collection.signed_editor.sub(/.\z/, collection.signed_editor.end_with?("a") ? "b" : "a")

    tampered_error = assert_raises(ArgumentError) do
      RecordingStudioAttachable::AttachmentCollection.from_params(
        recording: parent,
        params: { signed_editor: tampered, rows: [] }
      )
    end
    other_error = assert_raises(ArgumentError) do
      RecordingStudioAttachable::AttachmentCollection.from_params(
        recording: Parent.new("parent-2"),
        params: { signed_editor: collection.signed_editor, rows: [] }
      )
    end

    assert_equal "This form is out of date. Reload the page and try again.", tampered_error.message
    assert_equal "This form is out of date. Reload the page and try again.", other_error.message
  end

  def test_splice_replaces_association_slots_and_leaves_other_children
    file_a = child("file-a")
    image_1 = child("image-1", caption: "One")
    file_b = child("file-b")
    image_2 = child("image-2", caption: "Two")
    parent = orderable_parent([file_a, image_1, file_b, image_2])
    collection = with_membership([image_1, image_2]) do
      RecordingStudioAttachable::AttachmentCollection.for(
        recording: parent, association: :images, fields: [:caption], sortable: true
      )
    end

    saved = with_membership([image_1, image_2]) do
      RecordingStudioAttachable::AttachmentCollection.from_params(
        recording: parent,
        params: {
          signed_editor: collection.signed_editor,
          rows: [
            { recording_id: "image-2", order: "1", caption: "Two" },
            { recording_id: "image-1", order: "2", caption: "One" }
          ]
        }
      )
    end

    assert_equal %w[file-a image-2 file-b image-1], saved.reorder_ids
    assert_empty saved.revisions
  end

  def test_reorder_ids_are_nil_when_the_splice_matches_the_current_children
    file_a = child("file-a")
    image_1 = child("image-1")
    file_b = child("file-b")
    image_2 = child("image-2")
    parent = orderable_parent([file_a, image_1, file_b, image_2])
    collection = with_membership([image_1, image_2]) do
      RecordingStudioAttachable::AttachmentCollection.for(
        recording: parent, association: :images, fields: [:caption], sortable: true
      )
    end

    saved = with_membership([image_1, image_2]) do
      RecordingStudioAttachable::AttachmentCollection.from_params(
        recording: parent,
        params: {
          signed_editor: collection.signed_editor,
          rows: [
            { recording_id: "image-1", order: "1", caption: nil },
            { recording_id: "image-2", order: "2", caption: nil }
          ]
        }
      )
    end

    assert_nil saved.reorder_ids
  end

  def test_empty_messages_and_permit_drop_client_field_lists
    assert_equal "No images yet.", message_for(:images)
    assert_equal "No files yet.", message_for(:files)
    assert_equal "Nothing here yet.", message_for(:attachments)

    permitted = RecordingStudioAttachable::AttachmentCollection.permit(
      ActionController::Parameters.new(
        redirect_mode: "return_to",
        return_to: "/pages/1",
        attachment_collection: {
          signed_editor: "token",
          fields: ["caption"],
          association: "images",
          sortable: true,
          signed_blob_id: "blob",
          rows: [{ recording_id: "1", caption: "A", alt_text: "B", signed_blob_id: "blob" }]
        }
      )
    )

    assert_equal "token", permitted.dig(:attachment_collection, :signed_editor)
    assert_nil permitted.dig(:attachment_collection, :fields)
    assert_nil permitted.dig(:attachment_collection, :association)
    assert_nil permitted.dig(:attachment_collection, :sortable)
    assert_nil permitted.dig(:attachment_collection, :signed_blob_id)
    assert_equal "A", permitted.dig(:attachment_collection, :rows, 0, :caption)
    assert_equal "B", permitted.dig(:attachment_collection, :rows, 0, :alt_text)
    assert_nil permitted.dig(:attachment_collection, :rows, 0, :signed_blob_id)
    assert_equal "return_to", permitted[:redirect_mode]
    assert_equal "/pages/1", permitted[:return_to]
  end

  private

  def message_for(association)
    with_membership([]) do
      RecordingStudioAttachable::AttachmentCollection.for(
        recording: Parent.new("parent-1"),
        association: association,
        fields: [:caption],
        sortable: false
      ).empty_message
    end
  end

  def with_membership(recordings, &)
    query = Object.new
    query.define_singleton_method(:unpaged) { recordings }
    RecordingStudioAttachable::Queries::ForRecording.stub(:new, lambda { |**kwargs|
      @query_kwargs = kwargs
      query
    }, &)
  end

  def orderable_parent(children)
    parent = Parent.new("parent-1")
    parent.define_singleton_method(:recording_studio_orderable_children) { children }
    parent.define_singleton_method(:recording_studio_orderable_reorder!) { |**| nil }
    parent
  end

  def child(id, created_at: Time.utc(2026, 1, 1), **texts)
    Child.new(
      id: id,
      created_at: created_at,
      recordable: Snapshot.new(
        name: texts.fetch(:name, id),
        description: texts[:description],
        caption: texts[:caption],
        credit: texts[:credit],
        alt_text: texts[:alt_text],
        original_filename: "#{id}.png"
      )
    )
  end
end
