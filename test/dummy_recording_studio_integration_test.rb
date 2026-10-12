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
    register_library_and_attachable!
    load_dummy_recordables!
    register_library_and_attachable!
    RecordingStudioAttachable::Engine.enable_library_attachments!
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

    assert_not RecordingStudio.root_allowed?("User")
    assert_equal ["Workspace"], RecordingStudio.declared_allowed_parent_types_for("User")

    assert_not RecordingStudio.root_allowed?("Gallery")
    assert_equal ["Workspace"], RecordingStudio.declared_allowed_parent_types_for("Gallery")

    assert_not RecordingStudio.root_allowed?("RecordingStudioLibrary::Library")
    assert_not RecordingStudio.root_allowed?("RecordingStudioLibrary::Placement")

    assert_not RecordingStudio.root_allowed?("RecordingStudioAttachable::Attachment")
    assert_equal [], RecordingStudio.declared_allowed_parent_types_for("RecordingStudioAttachable::Attachment")
  end

  def test_dummy_app_attachable_capability_registers_attachment_as_capability_child
    registration = RecordingStudio.registered_capabilities.fetch(:attachable)

    assert_equal RecordingStudio::Capabilities::Attachable::RecordingMethods, registration.fetch(:recording_methods)
    assert_equal "recording_studio_attachable", registration.fetch(:source)
    assert_equal ["RecordingStudioAttachable::Attachment"], registration.fetch(:child_recordables)
    assert_equal ["RecordingStudioAttachable::Attachment"], RecordingStudio.capability_child_recordables_for(:attachable)
    assert_includes RecordingStudio.allowed_parent_types_for("RecordingStudioAttachable::Attachment"), "Page"
    assert_includes RecordingStudio.allowed_parent_types_for("RecordingStudioAttachable::Attachment"), "Workspace"
  end

  def test_dummy_app_image_library_and_placement_capabilities
    load File.expand_path("dummy/app/models/gallery.rb", __dir__)
    load File.expand_path("dummy/app/models/workspace.rb", __dir__)
    load_library_models!
    register_library_and_attachable!
    RecordingStudioAttachable::Engine.enable_library_attachments!

    assert RecordingStudio.capability_enabled?(:library, for: "Workspace")
    assert RecordingStudio.capability_enabled?(:image_library, for: "Workspace")
    assert RecordingStudio.capability_enabled?(:placeable, for: "Gallery")
    assert RecordingStudio.capability_enabled?(:library_placement, for: "Gallery")
    assert_includes RecordingStudio.allowed_parent_types_for("RecordingStudioLibrary::Library"), "Workspace"
    assert_includes RecordingStudio.allowed_parent_types_for("RecordingStudioLibrary::Placement"), "Gallery"
    assert_includes RecordingStudio.allowed_parent_types_for("RecordingStudioAttachable::Attachment"), "RecordingStudioLibrary::Library"
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
    assert_equal 1, RecordingStudio.capability_options(:attachable, for: "Page")[:max_file_count]
    assert_equal ["image/*"], RecordingStudio.capability_options(:attachable, for: "Page")[:allowed_content_types]
    assert_equal %i[image], RecordingStudio.capability_options(:attachable, for: "Page")[:enabled_attachment_kinds]
    refute RecordingStudio.capability_enabled?(:attachable, for: "User")
    refute RecordingStudio.capability_enabled?(:attachable, for: "ChatThread")
    refute RecordingStudio.capability_enabled?(:attachable, for: "ChatMessage")
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
    load_user_recordable!
    load File.expand_path("dummy/app/models/chat_message.rb", __dir__)
    load File.expand_path("dummy/app/models/gallery.rb", __dir__)
    load_library_models!
  end

  def load_library_models!
    gem_root = Gem.loaded_specs.fetch("recording_studio_library").full_gem_path
    load File.join(gem_root, "app/models/recording_studio_library/library.rb")
    load File.join(gem_root, "app/models/recording_studio_library/placement.rb")
    sample = File.join(gem_root, "app/models/recording_studio_library/sample_item.rb")
    load sample if File.exist?(sample)
  end

  def register_library_and_attachable!
    RecordingStudioLibrary::Engine.register_library_capabilities
    RecordingStudioAttachable::Engine.register_recording_studio_integration
  end

  def load_user_recordable!
    return if defined?(User) && User.respond_to?(:recording_studio_recordable_options)

    Object.send(:remove_const, :User) if Object.const_defined?(:User)

    ApplicationRecord.class_eval do
      def self.devise(*); end unless respond_to?(:devise)
    end

    load File.expand_path("dummy/app/models/user.rb", __dir__)
  end

  def recordable_types
    %w[
      Workspace
      Page
      User
      ChatThread
      ChatMessage
      Gallery
      RecordingStudioAttachable::Attachment
      RecordingStudioLibrary::Library
      RecordingStudioLibrary::Placement
      RecordingStudioLibrary::SampleItem
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
