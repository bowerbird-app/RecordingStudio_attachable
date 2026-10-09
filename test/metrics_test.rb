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

  def test_access_denies_without_an_admin_root
    actor = Object.new
    grant = Struct.new(:actor).new(actor)
    context = Object.new
    context.define_singleton_method(:access_grant) { grant }

    refute RecordingStudioAttachable::Api::Access.can_view?(context)
    refute RecordingStudioAttachable::Api::Access.can_view?(nil)
  end

  def test_site_resolver_is_preferred_when_set
    site_recording = Object.new
    access_recording = Object.new
    seen = nil
    access_called = false
    configuration = admin_configuration_double(
      site: lambda do |context|
        seen = context
        site_recording
      end,
      access: lambda do |_context|
        access_called = true
        access_recording
      end
    )

    with_admin_configuration(configuration) do
      assert_same site_recording, RecordingStudioAttachable::Api::Access.admin_root_recording
    end

    assert_instance_of RecordingStudioAttachable::Api::Access::ResolverContext, seen
    assert_nil seen.controller
    refute access_called
  end

  def test_access_resolver_is_used_when_the_site_resolver_is_unset
    access_recording = Object.new
    configuration = admin_configuration_double(
      site: nil,
      access: ->(_context) { access_recording }
    )

    with_admin_configuration(configuration) do
      assert_same access_recording, RecordingStudioAttachable::Api::Access.admin_root_recording
    end
  end

  def test_resolver_raising_denies_without_an_exception
    access_called = false
    configuration = admin_configuration_double(
      site: ->(_context) { raise NoMethodError, "undefined method `controller'" },
      access: lambda do |_context|
        access_called = true
        Object.new
      end
    )
    context = access_context_for(Object.new)
    result = nil

    with_admin_configuration(configuration) do
      result = RecordingStudioAttachable::Api::Access.can_view?(context)
    end

    assert_equal false, result
    refute access_called
  end

  def test_resolver_returning_nil_denies
    access_called = false
    configuration = admin_configuration_double(
      site: ->(_context) {},
      access: lambda do |_context|
        access_called = true
        Object.new
      end
    )
    context = access_context_for(Object.new)
    result = nil

    with_admin_configuration(configuration) do
      result = RecordingStudioAttachable::Api::Access.can_view?(context)
    end

    assert_equal false, result
    refute access_called
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

  def admin_configuration_double(site:, access:)
    Struct.new(:site_admin_recording_resolver, :access_recording_resolver).new(site, access)
  end

  def with_admin_configuration(configuration, &)
    RecordingStudioAttachable::Api::Access.stub(:admin_configuration, configuration, &)
  end

  def access_context_for(actor)
    grant = Struct.new(:actor).new(actor)
    context = Object.new
    context.define_singleton_method(:access_grant) { grant }
    context
  end
end
