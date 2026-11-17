# frozen_string_literal: true

require "test_helper"
require "stringio"

class OwnerAvailabilityTest < Minitest::Test
  Auth = RecordingStudioAttachable::Authorization

  class Boom < StandardError; end

  class OpenOwner
    attr_reader :seen

    def initialize(result)
      @result = result
    end

    def attachable_available_for?(actor:, action:, recording:)
      @seen = [actor, action, recording]
      @result.respond_to?(:call) ? @result.call : @result
    end
  end

  class PlainOwner
    def label
      "plain"
    end
  end

  class ClassMethodOwner
    def self.attachable_available_for?(**)
      false
    end
  end

  class PrivateOwner
    def attachable_available_for?(**)
      @called = true
      true
    end
    private :attachable_available_for?

    def called?
      @called == true
    end
  end

  class ProtectedOwner
    def attachable_available_for?(**)
      @called = true
      true
    end
    protected :attachable_available_for?

    def called?
      @called == true
    end
  end

  class RaisingOwner
    def attachable_available_for?(**)
      raise Boom, "secret draft reason"
    end
  end

  class SneakyTrue
    def ==(_other)
      true
    end
  end

  class RecordingDouble
    attr_accessor :recordable_type, :stored_recordable, :parent_recording
    attr_reader :recordable_calls

    def initialize(recordable_type:, recordable: nil, parent_recording: nil)
      @recordable_type = recordable_type
      @stored_recordable = recordable
      @parent_recording = parent_recording
      @recordable_calls = 0
    end

    def recordable
      @recordable_calls += 1
      stored_recordable
    end
  end

  def setup
    @original_configuration = RecordingStudioAttachable.instance_variable_get(:@configuration)
    @original_studio_configuration = RecordingStudio.method(:configuration)
    RecordingStudioAttachable.instance_variable_set(:@configuration, RecordingStudioAttachable::Configuration.new)
    stub_recording_studio!
    stub_accessible!
  end

  def teardown
    RecordingStudioAttachable.instance_variable_set(:@configuration, @original_configuration)
    RecordingStudio.define_singleton_method(:configuration, @original_studio_configuration)
  end

  def test_true_allows_and_passes_the_owner_recording
    owner = OpenOwner.new(true)
    recording = recording_for(owner)

    assert allowed?(recording: recording, actor: :actor, action: :download)
    assert_equal [:actor, :download, recording], owner.seen
    assert_equal 1, recording.recordable_calls
    assert Auth.authorize!(action: :download, actor: :actor, recording: recording)
  end

  def test_false_nil_and_other_objects_refuse
    [false, nil, :available, SneakyTrue.new].each do |result|
      owner = OpenOwner.new(result)
      recording = recording_for(owner)

      assert_not allowed?(recording: recording), result.inspect
      error = assert_raises(Auth::OwnerUnavailableError) do
        Auth.authorize!(action: :view, actor: :actor, recording: recording)
      end
      assert_kind_of Auth::NotAuthorizedError, error
      assert_equal "Not authorized to view attachments for OwnerAvailabilityTest::OpenOwner", error.message
    end
  end

  def test_owner_without_the_hook_does_not_load_the_recordable
    recording = recording_for(PlainOwner.new, "OwnerAvailabilityTest::PlainOwner")

    assert allowed?(recording: recording)
    assert_equal 0, recording.recordable_calls
    assert Auth.authorize!(action: :view, actor: :actor, recording: recording)
  end

  def test_class_method_is_ignored
    recording = recording_for(ClassMethodOwner.new, "OwnerAvailabilityTest::ClassMethodOwner")

    assert allowed?(recording: recording)
    assert_equal 0, recording.recordable_calls
  end

  def test_private_and_protected_methods_refuse_without_loading_or_calling
    [PrivateOwner, ProtectedOwner].each do |owner_class|
      owner = owner_class.new
      recording = recording_for(owner, owner_class.name)
      logs = capture_logs do
        assert_not allowed?(recording: recording), owner_class.name
      end

      assert_equal 0, recording.recordable_calls
      assert_not owner.called?
      assert_empty logs
    end
  end

  def test_a_raised_error_refuses_and_logs_the_class_only
    recording = recording_for(RaisingOwner.new, "OwnerAvailabilityTest::RaisingOwner")
    error = nil
    logs = capture_logs do
      assert_not allowed?(recording: recording)
      error = assert_raises(Auth::OwnerUnavailableError) do
        Auth.authorize!(action: :view, actor: :actor, recording: recording)
      end
    end

    assert_includes logs, "Boom"
    assert_not_includes logs, "secret draft reason"
    assert_not_includes error.message, "secret draft reason"
  end

  def test_role_refusal_does_not_call_the_hook
    owner = OpenOwner.new(true)
    recording = recording_for(owner)

    assert_not allowed?(recording: recording, capability_options: { authorize_with: ->(**) { false } })
    assert_nil owner.seen
    error = assert_raises(Auth::NotAuthorizedError) do
      Auth.authorize!(
        action: :view,
        actor: :actor,
        recording: recording,
        capability_options: { authorize_with: ->(**) { false } }
      )
    end
    assert_equal Auth::NotAuthorizedError, error.class
  end

  def test_hook_on_an_attachment_recordable_is_not_the_owner_hook
    parent = recording_for(PlainOwner.new, "OwnerAvailabilityTest::PlainOwner")
    attachment = RecordingDouble.new(
      recordable_type: "RecordingStudioAttachable::Attachment",
      recordable: OpenOwner.new(false),
      parent_recording: parent
    )

    assert allowed?(recording: attachment)
    assert_nil attachment.stored_recordable.seen
    assert_equal 0, parent.recordable_calls
  end

  def test_attachment_recording_uses_the_parent_recordable
    owner = OpenOwner.new(false)
    parent = recording_for(owner)
    attachment = RecordingDouble.new(
      recordable_type: "RecordingStudioAttachable::Attachment",
      parent_recording: parent
    )

    assert_not allowed?(recording: attachment, actor: :actor, action: :view)
    assert_equal [:actor, :view, parent], owner.seen
  end

  private

  def recording_for(recordable, recordable_type = "OwnerAvailabilityTest::OpenOwner")
    RecordingDouble.new(recordable_type: recordable_type, recordable: recordable)
  end

  def allowed?(recording:, actor: :actor, action: :view, capability_options: nil)
    Auth.allowed?(action: action, actor: actor, recording: recording, capability_options: capability_options)
  end

  def capture_logs(&)
    io = StringIO.new
    logger = Logger.new(io)
    Rails.stub(:logger, logger, &)
    io.string
  end

  def stub_recording_studio!
    studio = defined?(RecordingStudio) ? RecordingStudio : Object.const_set(:RecordingStudio, Module.new)
    configuration = Class.new do
      def capability_enabled?(*)
        true
      end

      def capability_options(*)
        {}
      end
    end.new
    studio.instance_variable_set(:@test_configuration, configuration)
    studio.singleton_class.send(:remove_method, :configuration) if studio.singleton_class.method_defined?(:configuration)
    studio.define_singleton_method(:configuration) { @test_configuration }
  end

  def stub_accessible!
    return if defined?(RecordingStudioAccessible::Authorization)

    accessible = Module.new
    accessible.singleton_class.class_eval do
      define_method(:allowed?) { |actor:, recording:, role:| actor || recording || role || true }
    end
    Object.const_set(:RecordingStudioAccessible, Module.new) unless defined?(RecordingStudioAccessible)
    RecordingStudioAccessible.const_set(:Authorization, accessible)
  end
end
