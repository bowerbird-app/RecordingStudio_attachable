# frozen_string_literal: true

require "test_helper"

class UploadRightsTest < Minitest::Test
  def test_require_accepts_only_true
    RecordingStudioAttachable::UploadRights.require!(true)

    [nil, false, "yes", "true", 1].each do |value|
      error = assert_raises(ArgumentError) do
        RecordingStudioAttachable::UploadRights.require!(value)
      end
      assert_equal RecordingStudioAttachable::UploadRights::REFUSED, error.message
    end
  end

  def test_chatgpt_client_detection
    assert_equal true, RecordingStudioAttachable::UploadRights.chatgpt_client("openai-mcp")
    assert_equal true, RecordingStudioAttachable::UploadRights.chatgpt_client({ name: "ChatGPT" })
    assert_equal true, RecordingStudioAttachable::UploadRights.chatgpt_client(
      Struct.new(:client_info).new({ "name" => "OpenAI" })
    )
    assert_equal false, RecordingStudioAttachable::UploadRights.chatgpt_client("cursor")
    assert_nil RecordingStudioAttachable::UploadRights.chatgpt_client(nil)
    assert_nil RecordingStudioAttachable::UploadRights.chatgpt_client(Object.new)
  end

  def test_field_tells_the_ai_to_ask_the_user
    field = RecordingStudioAttachable::McpCopy.rights_confirmed_field

    assert_equal "boolean", field.fetch("type")
    assert_includes field.fetch("description"), RecordingStudioAttachable::UploadRights::QUESTION
    assert_includes field.fetch("description"), "send true only if they say yes"
  end
end
