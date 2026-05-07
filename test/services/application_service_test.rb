# frozen_string_literal: true

require "test_helper"
require_relative "../../app/services/recording_studio_attachable/services/application_service"

module RecordingStudioAttachable
  module Services
    class ApplicationServiceTest < Minitest::Test
      RecordingDouble = Struct.new(:id, :recordable_type, :root_recording, :parent_recording, keyword_init: true)
      AttachmentDouble = Struct.new(:id, :name, :attachment_kind, :original_filename, :content_type, :byte_size, keyword_init: true)
      BlobDouble = Struct.new(:content_type, :byte_size)

      class ProbeService < ApplicationService
        def require_recording_studio_public!
          send(:require_recording_studio!)
        end

        def resolve_actor_public(explicit_actor)
          send(:resolve_actor, explicit_actor)
        end

        def attachment_recording_public(recording)
          send(:attachment_recording!, recording)
        end

        def attachment_owner_recording_public(recording)
          send(:attachment_owner_recording!, recording)
        end

        def validate_blob_public(blob, capability_options: {})
          send(:validate_blob!, blob, capability_options: capability_options)
        end

        def transaction_wrapper_public(&)
          send(:transaction_wrapper, &)
        end

        private

        def perform
          success(true)
        end
      end

      def setup
        @original_configuration = RecordingStudioAttachable.instance_variable_get(:@configuration)
        RecordingStudioAttachable.instance_variable_set(:@configuration, RecordingStudioAttachable::Configuration.new)
        @service = ProbeService.new
      end

      def teardown
        RecordingStudioAttachable.instance_variable_set(:@configuration, @original_configuration)
      end

      def test_require_recording_studio_raises_when_the_constant_is_missing
        original = Object.send(:remove_const, :RecordingStudio) if defined?(RecordingStudio)

        error = assert_raises(RecordingStudioAttachable::DependencyUnavailableError) do
          @service.require_recording_studio_public!
        end

        assert_equal "RecordingStudio must be loaded to use RecordingStudioAttachable", error.message
      ensure
        Object.const_set(:RecordingStudio, original) if original
      end

      def test_resolve_actor_prefers_explicit_actor_then_current_actor
        current = ensure_current_class
        current.define_singleton_method(:actor) { :current_actor }

        assert_equal :explicit_actor, @service.resolve_actor_public(:explicit_actor)
        assert_equal :current_actor, @service.resolve_actor_public(nil)
      ensure
        current.singleton_class.send(:remove_method, :actor) if defined?(current) && current.respond_to?(:actor)
      end

      def test_attachment_recording_raises_for_non_attachment_recordings
        recording = RecordingDouble.new(id: "rec-1", recordable_type: "Workspace")

        error = assert_raises(ArgumentError) do
          @service.attachment_recording_public(recording)
        end

        assert_equal "Recording is not an attachment", error.message
      end

      def test_attachment_owner_recording_raises_when_parent_is_missing
        recording = RecordingDouble.new(id: "rec-1", recordable_type: "RecordingStudioAttachable::Attachment", parent_recording: nil)

        error = assert_raises(ArgumentError) do
          @service.attachment_owner_recording_public(recording)
        end

        assert_equal "Attachment recording must belong to a parent recording", error.message
      end

      def test_validate_blob_rejects_disallowed_content_types
        blob = BlobDouble.new("text/plain", 128)

        error = assert_raises(ArgumentError) do
          @service.validate_blob_public(blob)
        end

        assert_includes error.message, "Blob content type \"text/plain\" is not allowed"
      end

      def test_validate_blob_rejects_oversized_blobs
        blob = BlobDouble.new("image/png", 1025)

        error = assert_raises(ArgumentError) do
          @service.validate_blob_public(blob, capability_options: { max_file_size: 1024, allowed_content_types: ["image/*"] })
        end

        assert_equal "Blob exceeds maximum file size", error.message
      end

      def test_transaction_wrapper_uses_recording_studio_transaction_when_available
        calls = []
        studio = defined?(RecordingStudio) ? RecordingStudio : Object.const_set(:RecordingStudio, Module.new)
        original_recording = RecordingStudio.send(:remove_const, :Recording) if defined?(RecordingStudio::Recording)
        recording_class = Class.new do
          def self.transaction
            yield
          end
        end
        recording_class.define_singleton_method(:transaction) do |&block|
          calls << :transaction
          block.call
        end
        studio.const_set(:Recording, recording_class)

        result = @service.transaction_wrapper_public do
          calls << :yielded
          :ok
        end

        assert_equal :ok, result
        assert_equal %i[transaction yielded], calls
      ensure
        RecordingStudio.send(:remove_const, :Recording) if defined?(RecordingStudio::Recording)
        RecordingStudio.const_set(:Recording, original_recording) if defined?(original_recording) && original_recording
      end

      def test_transaction_wrapper_falls_back_when_recording_transaction_is_unavailable
        studio = defined?(RecordingStudio) ? RecordingStudio : Object.const_set(:RecordingStudio, Module.new)
        original_recording = RecordingStudio.send(:remove_const, :Recording) if defined?(RecordingStudio::Recording)
        studio.const_set(:Recording, Class.new)
        calls = []

        result = @service.transaction_wrapper_public do
          calls << :yielded
          :ok
        end

        assert_equal :ok, result
        assert_equal [:yielded], calls
      ensure
        RecordingStudio.send(:remove_const, :Recording) if defined?(RecordingStudio::Recording)
        RecordingStudio.const_set(:Recording, original_recording) if defined?(original_recording) && original_recording
      end

      private

      def ensure_current_class
        return Current if defined?(Current)

        Object.const_set(:Current, Class.new)
      end
    end
  end
end
