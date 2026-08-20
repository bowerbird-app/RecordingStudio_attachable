# frozen_string_literal: true

require "test_helper"

class DummyRecordingStudioIntegrationTest < ActiveSupport::TestCase
  def setup
    restore_recording_studio_api!
    @original_types = RecordingStudio.configuration.recordable_types
    @original_capabilities = copy_capabilities
    @original_registered_capabilities = copy_registered_capabilities
    @original_declarations = RecordingStudio::RecordableDeclarations.declarations

    ensure_application_record!
    load_dummy_recordables!
    RecordingStudioAttachable::Engine.register_recording_studio_integration
  end

  def teardown
    RecordingStudio.configuration.recordable_types = @original_types
    RecordingStudio.configuration.instance_variable_set(:@capabilities, @original_capabilities)
    RecordingStudio.instance_variable_set(:@registered_capabilities, @original_registered_capabilities)
    RecordingStudio::RecordableDeclarations.replace_declarations!(@original_declarations)
  end

  def test_dummy_app_recordables_have_recording_studio_hierarchy_declarations
    assert RecordingStudio.validate_recordable_declarations!

    assert RecordingStudio.root_allowed?("Workspace")
    assert_equal [], RecordingStudio.declared_allowed_parent_types_for("Workspace")

    assert_not RecordingStudio.root_allowed?("Page")
    assert_equal ["Workspace"], RecordingStudio.declared_allowed_parent_types_for("Page")

    assert_not RecordingStudio.root_allowed?("ChatThread")
    assert_equal ["Workspace"], RecordingStudio.declared_allowed_parent_types_for("ChatThread")

    assert_not RecordingStudio.root_allowed?("ChatMessage")
    assert_equal ["ChatThread"], RecordingStudio.declared_allowed_parent_types_for("ChatMessage")

    assert_not RecordingStudio.root_allowed?("RecordingStudioAttachable::Attachment")
    assert_equal [], RecordingStudio.declared_allowed_parent_types_for("RecordingStudioAttachable::Attachment")
  end

  def test_dummy_app_attachable_capability_registers_attachment_as_capability_child
    registration = RecordingStudio.registered_capabilities.fetch(:attachable)

    assert_equal RecordingStudio::Capabilities::Attachable::RecordingMethods, registration.fetch(:recording_methods)
    assert_equal "recording_studio_attachable", registration.fetch(:source)
    assert_equal ["RecordingStudioAttachable::Attachment"], registration.fetch(:child_recordables)
    assert_equal ["RecordingStudioAttachable::Attachment"], RecordingStudio.capability_child_recordables_for(:attachable)
    assert_equal %w[Page Workspace], RecordingStudio.allowed_parent_types_for("RecordingStudioAttachable::Attachment")
  end

  def test_dummy_app_attachable_capability_options_are_available_for_parent_types
    assert_equal(
      {
        allowed_content_types: ["image/*", "application/pdf", "text/plain"],
        max_file_size: 25.megabytes,
        enabled_attachment_kinds: %i[image file]
      },
      RecordingStudio.capability_options(:attachable, for: "Workspace").slice(
        :allowed_content_types,
        :max_file_size,
        :enabled_attachment_kinds
      )
    )
    assert_equal ["image/*"], RecordingStudio.capability_options(:attachable, for: "Page")[:allowed_content_types]
    assert_equal %i[image], RecordingStudio.capability_options(:attachable, for: "Page")[:enabled_attachment_kinds]
  end

  private

  def ensure_application_record!
    return if defined?(ApplicationRecord)

    Object.const_set(
      :ApplicationRecord,
      Class.new(ActiveRecord::Base) do
        self.abstract_class = true
      end
    )
  end

  def restore_recording_studio_api!
    singleton_class = RecordingStudio.singleton_class
    %i[configuration capability_options record! register_recordable_type register_capability].each do |method_name|
      singleton_class.send(:remove_method, method_name) if singleton_class.method_defined?(method_name)
    end
    load File.join(Gem.loaded_specs.fetch("recording_studio").full_gem_path, "lib/recording_studio.rb")
  end

  def load_dummy_recordables!
    RecordingStudio.configuration.recordable_types = %w[Workspace RecordingStudioAttachable::Attachment]
    load File.expand_path("dummy/app/models/workspace.rb", __dir__)
    RecordingStudio.configuration.recordable_types = %w[Workspace Page RecordingStudioAttachable::Attachment]
    load File.expand_path("dummy/app/models/page.rb", __dir__)
    RecordingStudio.configuration.recordable_types = %w[Workspace Page ChatThread RecordingStudioAttachable::Attachment]
    load File.expand_path("dummy/app/models/chat_thread.rb", __dir__)
    RecordingStudio.configuration.recordable_types = recordable_types
    load File.expand_path("dummy/app/models/chat_message.rb", __dir__)
  end

  def recordable_types
    %w[
      Workspace
      Page
      ChatThread
      ChatMessage
      RecordingStudioAttachable::Attachment
    ]
  end

  def copy_capabilities
    capabilities = RecordingStudio.configuration.instance_variable_get(:@capabilities) || {}
    capabilities.transform_values(&:dup)
  end

  def copy_registered_capabilities
    RecordingStudio.registered_capabilities.transform_values do |registration|
      registration.merge(child_recordables: Array(registration[:child_recordables]).dup.freeze)
    end
  end
end
