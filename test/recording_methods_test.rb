# frozen_string_literal: true

require "test_helper"
require_relative "../app/queries/recording_studio_attachable/queries/for_recording"
require_relative "../app/services/recording_studio_attachable/services/application_service"
require_relative "../app/services/recording_studio_attachable/services/remove_attachments"

class RecordingMethodsTest < Minitest::Test
  class FakeRecording
    include RecordingStudio::Capabilities::Attachable::RecordingMethods

    attr_reader :recordable_type

    def initialize(recordable_type = "Workspace")
      @recordable_type = recordable_type
    end

    private

    def assert_capability!(*); end
  end

  def test_attachments_delegates_search_and_pagination_to_the_query
    recording = FakeRecording.new
    fake_query = Minitest::Mock.new
    fake_query.expect(:call, [:attachments])
    captured_kwargs = nil

    RecordingStudioAttachable::Queries::ForRecording.stub(:new, lambda { |**kwargs|
      captured_kwargs = kwargs
      fake_query
    }) do
      result = recording.attachments(search: "brief", page: 3, per_page: 12, scope: :subtree, kind: :files)

      assert_equal [:attachments], result
    end

    fake_query.verify
    assert_equal recording, captured_kwargs[:recording]
    assert_equal "brief", captured_kwargs[:search]
    assert_equal 3, captured_kwargs[:page]
    assert_equal 12, captured_kwargs[:per_page]
    assert_equal :subtree, captured_kwargs[:scope]
    assert_equal :files, captured_kwargs[:kind]
  end

  def test_remove_attachments_delegates_to_bulk_remove_service
    recording = FakeRecording.new
    result = RecordingStudioAttachable::Services::BaseService::Result.new(success: true, value: [:removed])
    captured_kwargs = nil

    RecordingStudioAttachable::Services::RemoveAttachments.stub(:call, lambda { |**kwargs|
      captured_kwargs = kwargs
      result
    }) do
      assert_equal [:removed], recording.remove_attachments(attachment_ids: ["att-1"], actor: :user)
    end

    assert_equal recording, captured_kwargs[:parent_recording]
    assert_equal ["att-1"], captured_kwargs[:attachment_ids]
    assert_equal :user, captured_kwargs[:actor]
  end
end
