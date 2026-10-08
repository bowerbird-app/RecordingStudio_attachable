# frozen_string_literal: true

require "test_helper"

class DirectUrlTest < Minitest::Test
  def setup
    @previous_host = RecordingStudioAttachable.configuration.direct_url_host
  end

  def teardown
    RecordingStudioAttachable.configuration.direct_url_host = @previous_host
  end

  def test_build_joins_https_host_and_blob_key
    RecordingStudioAttachable.configuration.direct_url_host = "images.featuredin.press"

    assert_equal(
      "https://images.featuredin.press/abc123xyz",
      RecordingStudioAttachable::DirectUrl.build("abc123xyz")
    )
  end

  def test_build_strips_scheme_and_trailing_slash_from_host
    assert_equal(
      "https://images.featuredin.press/key-1",
      RecordingStudioAttachable::DirectUrl.build(
        "key-1",
        host: "https://images.featuredin.press/"
      )
    )
  end

  def test_build_raises_when_host_is_missing
    RecordingStudioAttachable.configuration.direct_url_host = nil

    error = assert_raises(RecordingStudioAttachable::ConfigurationError) do
      RecordingStudioAttachable::DirectUrl.build("key-1")
    end

    assert_match(/direct_url_host must be set/, error.message)
  end

  def test_build_raises_when_blob_key_is_blank
    error = assert_raises(ArgumentError) do
      RecordingStudioAttachable::DirectUrl.build("", host: "images.example.com")
    end

    assert_match(/blob_key is required/, error.message)
  end
end
