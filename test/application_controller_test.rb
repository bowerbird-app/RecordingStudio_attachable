# frozen_string_literal: true

require "test_helper"

class ApplicationControllerTest < Minitest::Test
  class LayoutProbeController < RecordingStudioAttachable::ApplicationController; end

  def setup
    @original_layout = RecordingStudioAttachable.configuration.layout
    @controller = LayoutProbeController.new
  end

  def teardown
    RecordingStudioAttachable.configuration.layout = @original_layout
  end

  def test_blank_layout_is_default
    RecordingStudioAttachable.configuration.layout = :blank

    assert_equal "recording_studio_attachable/blank", @controller.send(:recording_studio_attachable_layout)
  end

  def test_legacy_blank_upload_alias_still_uses_blank_layout
    RecordingStudioAttachable.configuration.layout = :blank_upload

    assert_equal "recording_studio_attachable/blank", @controller.send(:recording_studio_attachable_layout)
  end

  def test_custom_layout_can_be_provided_by_host_app
    RecordingStudioAttachable.configuration.layout = "application"

    assert_equal "application", @controller.send(:recording_studio_attachable_layout)
  end
end
