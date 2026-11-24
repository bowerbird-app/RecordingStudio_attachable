# frozen_string_literal: true

require "test_helper"

class AttachmentPayloadTest < Minitest::Test
  FakeAttachment = Struct.new(:attachment_kind, :name, :url, keyword_init: true) do
    def original_url(mode: nil, rails_url: nil)
      raise RecordingStudioAttachable::ConfigurationError, RecordingStudioAttachable::DirectUrl.missing_host_message if url == :missing

      return "https://images.example.test/blob-key" if mode == :direct || url == :direct

      rails_url
    end
  end
  FakeRecording = Struct.new(:id, :recordable, keyword_init: true)

  def setup
    @previous = RecordingStudioAttachable.configuration
    RecordingStudioAttachable.instance_variable_set(:@configuration, RecordingStudioAttachable::Configuration.new)
  end

  def teardown
    RecordingStudioAttachable.instance_variable_set(:@configuration, @previous)
  end

  def test_authorized_viewer_receives_the_rails_file_url
    payload = payload_for(actor_allowed: true, rails_url: "/attachments/9/file")

    assert_equal "rec-9", payload[:id]
    assert_equal "image", payload[:kind]
    assert_equal "Cover", payload[:name]
    assert_equal "/attachments/9/file", payload.dig(:urls, :file)
    assert_equal %i[id kind name urls], payload.keys
    assert_nil payload.dig(:urls, :file_url)
  end

  def test_file_url_is_absolute_when_a_public_host_is_configured
    RecordingStudioAttachable.configuration.public_url_host = "files.example.test"
    payload = payload_for(actor_allowed: true, rails_url: "/attachments/9/file")

    assert_equal "/attachments/9/file", payload.dig(:urls, :file)
    assert_equal "https://files.example.test/attachments/9/file", payload.dig(:urls, :file_url)
  end

  def test_file_url_is_omitted_without_a_host_and_in_direct_mode
    payload = payload_for(actor_allowed: true, rails_url: "/attachments/9/file")
    assert_nil payload.dig(:urls, :file_url)

    RecordingStudioAttachable.configuration.public_url_host = "files.example.test"
    RecordingStudioAttachable.configuration.direct_url_host = "images.example.test"
    direct = payload_for(actor_allowed: true, url: :direct, url_mode: :direct, rails_url: "/attachments/9/file")

    assert_equal "https://images.example.test/blob-key", direct.dig(:urls, :file)
    assert_nil direct.dig(:urls, :file_url)
  end

  def test_unauthorized_viewer_receives_no_file_url
    attachment = FakeAttachment.new(attachment_kind: "image", name: "Cover", url: :missing)
    recording = FakeRecording.new(id: "rec-9", recordable: attachment)

    payload = RecordingStudioAttachable::Authorization.stub(:allowed?, false) do
      RecordingStudioAttachable.attachment_payload(recording, actor: :stranger, url_mode: :direct)
    end

    assert_nil payload.dig(:urls, :file)
    assert_equal "Cover", payload[:name]
  end

  def test_direct_mode_returns_the_host_url_and_raises_without_a_host
    RecordingStudioAttachable.configuration.direct_url_host = "images.example.test"
    hosted = payload_for(actor_allowed: true, url: :direct, url_mode: :direct, rails_url: "/attachments/9/file")
    assert_equal "https://images.example.test/blob-key", hosted.dig(:urls, :file)

    RecordingStudioAttachable.configuration.direct_url_host = nil
    error = assert_raises(RecordingStudioAttachable::ConfigurationError) do
      payload_for(actor_allowed: true, url: :missing, url_mode: :direct, rails_url: "/attachments/9/file")
    end
    assert_match(/direct_url_host must be set/, error.message)
    assert_equal false, RecordingStudioAttachable.direct_urls_available?
  end

  private

  def payload_for(actor_allowed:, rails_url:, url: nil, url_mode: nil)
    attachment = FakeAttachment.new(attachment_kind: "image", name: "Cover", url: url)
    recording = FakeRecording.new(id: "rec-9", recordable: attachment)
    RecordingStudioAttachable::Authorization.stub(:allowed?, actor_allowed) do
      RecordingStudioAttachable.attachment_payload(recording, actor: :viewer, url_mode: url_mode, rails_url: rails_url)
    end
  end
end
