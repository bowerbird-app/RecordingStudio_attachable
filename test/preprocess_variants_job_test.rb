# frozen_string_literal: true

require "test_helper"
require "active_job"
require_relative "../app/jobs/recording_studio_attachable/preprocess_variants_job"

module RecordingStudioAttachable
  class PreprocessVariantsJobTest < Minitest::Test
    def setup
      @previous_configuration = RecordingStudioAttachable.configuration
      RecordingStudioAttachable.instance_variable_set(:@configuration, Configuration.new)
    end

    def teardown
      RecordingStudioAttachable.instance_variable_set(:@configuration, @previous_configuration)
    end

    def test_perform_is_a_no_op_when_attachment_is_missing
      Attachment.stub(:find_by, nil) do
        assert_nil PreprocessVariantsJob.new.perform("missing-id")
      end
    end

    def test_perform_skips_non_variable_attachments
      file = Object.new
      file.define_singleton_method(:attached?) { true }
      file.define_singleton_method(:variable?) { false }
      file.define_singleton_method(:variant) { raise "should not process" }

      attachment = Object.new
      attachment.define_singleton_method(:file) { file }

      Attachment.stub(:find_by, attachment) do
        assert_nil PreprocessVariantsJob.new.perform("att-1")
      end
    end

    def test_perform_processes_each_configured_variant
      RecordingStudioAttachable.configuration.preprocessed_variants = %i[small med]

      processed_names = []
      file = Object.new
      file.define_singleton_method(:attached?) { true }
      file.define_singleton_method(:variable?) { true }
      file.define_singleton_method(:variant) do |transformations|
        Object.new.tap do |variant|
          variant.define_singleton_method(:processed) do
            processed_names << transformations
            self
          end
        end
      end

      attachment = Object.new
      attachment.define_singleton_method(:file) { file }

      Attachment.stub(:find_by, attachment) do
        PreprocessVariantsJob.new.perform("att-1")
      end

      assert_equal [
        { resize_to_limit: [480, 480] },
        { resize_to_limit: [960, 960] }
      ], processed_names
    end

    def test_perform_processes_host_added_poster_from_default_preprocessed_list
      RecordingStudioAttachable.configuration.image_variants = {
        poster: { resize_to_limit: [1280, 720] }
      }

      assert_includes RecordingStudioAttachable.configuration.preprocessed_variants, :poster

      processed_names = []
      file = Object.new
      file.define_singleton_method(:attached?) { true }
      file.define_singleton_method(:variable?) { true }
      file.define_singleton_method(:variant) do |transformations|
        Object.new.tap do |variant|
          variant.define_singleton_method(:processed) do
            processed_names << transformations
            self
          end
        end
      end

      attachment = Object.new
      attachment.define_singleton_method(:file) { file }

      Attachment.stub(:find_by, attachment) do
        PreprocessVariantsJob.new.perform("att-1")
      end

      assert_includes processed_names, { resize_to_limit: [1280, 720] }
      assert_equal 4, processed_names.size
    end

    def test_perform_is_safe_when_file_is_not_attached
      file = Object.new
      file.define_singleton_method(:attached?) { false }
      file.define_singleton_method(:variable?) { raise "should not check variable?" }

      attachment = Object.new
      attachment.define_singleton_method(:file) { file }

      Attachment.stub(:find_by, attachment) do
        assert_nil PreprocessVariantsJob.new.perform("att-1")
      end
    end
  end
end
