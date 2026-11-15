# frozen_string_literal: true

require "test_helper"
require "recording_studio_attachable/api/access"

class MetricsTest < Minitest::Test
  def test_engine_registers_metrics_on_to_prepare
    initializer = RecordingStudioAttachable::Engine.initializers.find do |item|
      item.name == "recording_studio_attachable.metrics"
    end

    assert initializer
    source = File.read(File.expand_path("../lib/recording_studio_attachable/engine.rb", __dir__))
    assert_includes source, "require \"recording_studio_attachable/metrics\""
    assert_includes source, "Metrics.register!"
  end

  def test_metrics_register_uses_can_view_api_authorize
    source = File.read(File.expand_path("../lib/recording_studio_attachable/metrics.rb", __dir__))

    assert_includes source, "RecordingStudioMetrics.register("
    assert_includes source, "api_authorize: ->(context) { RecordingStudioAttachable::Api::Access.can_view?(context) }"
    refute_includes source, "RecordingStudioMetrics::Api.register!"
  end

  def test_access_denies_without_an_admin_root
    actor = Object.new
    grant = Struct.new(:actor).new(actor)
    context = Object.new
    context.define_singleton_method(:access_grant) { grant }

    refute RecordingStudioAttachable::Api::Access.can_view?(context)
    refute RecordingStudioAttachable::Api::Access.can_view?(nil)
  end

  def test_admin_root_comes_from_accessible
    recording = Object.new

    with_admin_root(-> { recording }) do
      assert_same recording, RecordingStudioAttachable::Api::Access.admin_root_recording
    end
  end

  def test_admin_root_error_denies_without_an_exception
    context = access_context_for(Object.new)
    result = nil

    with_admin_root(-> { raise NoMethodError, "undefined method `controller'" }) do
      result = RecordingStudioAttachable::Api::Access.can_view?(context)
    end

    assert_equal false, result
  end

  def test_missing_admin_root_denies
    context = access_context_for(Object.new)

    with_admin_root(-> {}) do
      refute RecordingStudioAttachable::Api::Access.can_view?(context)
    end
  end

  def test_metrics_file_scopes_through_live_recordings
    source = File.read(File.expand_path("../lib/recording_studio_attachable/metrics.rb", __dir__))

    assert_includes source, "model: RecordingStudio::Recording"
    assert_includes source, "recordable_type: RECORDABLE_TYPE"
    assert_includes source, "trashed_at: nil"
    assert_includes source, "attachments[:id].eq(recordings[:recordable_id])"
    refute_includes source, "Attachment.all"
  end

  private

  def with_admin_root(resolver)
    original = nil
    if defined?(::RecordingStudioAccessible)
      original = ::RecordingStudioAccessible.method(:admin_root)
      ::RecordingStudioAccessible.define_singleton_method(:admin_root) { |**| resolver.call }
    else
      accessible = Module.new
      accessible.define_singleton_method(:admin_root) { |**| resolver.call }
      Object.const_set(:RecordingStudioAccessible, accessible)
    end

    yield
  ensure
    if original
      ::RecordingStudioAccessible.define_singleton_method(:admin_root, original)
    elsif defined?(::RecordingStudioAccessible)
      Object.send(:remove_const, :RecordingStudioAccessible)
    end
  end

  def access_context_for(actor)
    grant = Struct.new(:actor).new(actor)
    context = Object.new
    context.define_singleton_method(:access_grant) { grant }
    context
  end
end
