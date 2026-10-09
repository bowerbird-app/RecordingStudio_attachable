# frozen_string_literal: true

require "test_helper"

class MetricsTest < Minitest::Test
  def test_engine_registers_metrics_on_to_prepare
    initializer = RecordingStudioAttachable::Engine.initializers.find do |item|
      item.name == "recording_studio_attachable.metrics"
    end

    assert initializer
    source = File.read(File.expand_path("../lib/recording_studio_attachable/engine.rb", __dir__))
    assert_includes source, "config.to_prepare { RecordingStudioAttachable::Metrics.register! }"
  end

  def test_access_denies_without_an_admin_root
    actor = Object.new
    grant = Struct.new(:actor).new(actor)
    context = Object.new
    context.define_singleton_method(:access_grant) { grant }

    refute RecordingStudioAttachable::Api::Access.can_view?(context)
    refute RecordingStudioAttachable::Api::Access.can_view?(nil)
  end

  def test_metrics_file_scopes_through_live_recordings
    source = File.read(File.expand_path("../lib/recording_studio_attachable/metrics.rb", __dir__))

    assert_includes source, "RecordingStudio::Recording.where("
    assert_includes source, "recordable_type: RECORDABLE_TYPE"
    assert_includes source, "trashed_at: nil"
    assert_includes source, "recordings.select(:recordable_id)"
    refute_includes source, "Attachment.all"
  end
end
