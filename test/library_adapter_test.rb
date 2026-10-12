# frozen_string_literal: true

require "test_helper"

class LibraryAdapterTest < Minitest::Test
  FakeAttachment = Struct.new(:name, :caption, :credit, :alt_text, :description, :original_filename, :attachment_kind, :image, keyword_init: true) do
    def image?
      image
    end
  end
  FakeRecording = Struct.new(:recordable, :recordable_type, keyword_init: true)

  class FakeView
    def tag
      Tag.new
    end

    def image_tag(path, alt:, **options)
      %(<img src="#{path}" alt="#{alt}" class="#{options[:class]}">)
    end

    def authorized_attachment_preview_path(_recording, variant)
      "/preview/#{variant}"
    end

    def render(component)
      component
    end

    def safe_join(parts)
      parts.join
    end

    class Tag
      def div(**options)
        body = block_given? ? yield : ""
        %(<div class="#{options[:class]}">#{body}</div>)
      end

      def span(text, **options)
        %(<span class="#{options[:class]}">#{text}</span>)
      end
    end
  end

  def test_photo_adapter_label_icon_search_and_thumbnail
    recording = FakeRecording.new(
      recordable: FakeAttachment.new(
        name: "Kiln hero",
        caption: "Warm glaze",
        credit: "Ada",
        alt_text: "A kiln",
        original_filename: "hero.jpg",
        attachment_kind: "image",
        image: true
      ),
      recordable_type: "RecordingStudioAttachable::Attachment"
    )
    adapter = RecordingStudioAttachable::Adapters::Attachment.new(recording)
    view = FakeView.new

    assert_equal "Photo", adapter.type_label
    assert_equal :photo, adapter.icon
    assert_equal "Kiln hero", adapter.title
    assert_includes adapter.search_text, "Warm glaze"
    assert_includes adapter.search_text, "Ada"
    assert_includes adapter.thumbnail(view), "/preview/square_med"
    assert_includes adapter.preview(view), "/preview/square_small"
  end

  def test_file_adapter_uses_file_label_and_swatch
    recording = FakeRecording.new(
      recordable: FakeAttachment.new(
        name: "Spec sheet",
        attachment_kind: "file",
        original_filename: "spec.pdf",
        image: false
      ),
      recordable_type: "RecordingStudioAttachable::Attachment"
    )
    adapter = RecordingStudioAttachable::Adapters::Attachment.new(recording)

    assert_equal "File", adapter.type_label
    assert_equal :document, adapter.icon
    assert_includes adapter.thumbnail(FakeView.new), "S"
  end

  def test_add_button_label_without_a_recordable_is_photo
    recording = Struct.new(:recordable, :recordable_type).new(nil, "RecordingStudioAttachable::Attachment")
    adapter = RecordingStudioAttachable::Adapters::Attachment.new(recording)

    assert_equal "Photo", adapter.type_label
  end

  def test_edit_fields_reuse_caption_credit_and_alt
    recording = FakeRecording.new(
      recordable: FakeAttachment.new(
        name: "Kiln hero",
        caption: "Warm glaze",
        credit: "Ada",
        alt_text: "A kiln",
        attachment_kind: "image",
        image: true
      ),
      recordable_type: "RecordingStudioAttachable::Attachment"
    )
    form = Object.new
    form.define_singleton_method(:object_name) { "attachment" }
    adapter = RecordingStudioAttachable::Adapters::Attachment.new(recording)
    called = []
    adapter.define_singleton_method(:text_field) do |_view, _form, attribute, value, _key|
      called << [attribute, value]
      attribute.to_s
    end

    adapter.edit_fields(FakeView.new, form)

    assert_equal(
      [[:name, "Kiln hero"], [:caption, "Warm glaze"], [:credit, "Ada"], [:alt_text, "A kiln"]],
      called
    )
  end

  def test_full_view_uses_the_large_variant
    recording = FakeRecording.new(
      recordable: FakeAttachment.new(name: "Kiln hero", attachment_kind: "image", image: true),
      recordable_type: "RecordingStudioAttachable::Attachment"
    )

    assert_includes RecordingStudioAttachable::Adapters::Attachment.new(recording).full_view(FakeView.new), "/preview/large"
  end
end
