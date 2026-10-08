# frozen_string_literal: true

require "test_helper"
require "active_job"
require_relative "../app/jobs/recording_studio_attachable/preprocess_variants_job"

module RecordingStudioAttachable
  class PreprocessVariantsJobTest < Minitest::Test
    def setup
      @previous_variants = RecordingStudioAttachable.configuration.preprocessed_variants
      RecordingStudioAttachable.configuration.preprocessed_variants = %i[small med]
    end

    def teardown
      RecordingStudioAttachable.configuration.preprocessed_variants = @previous_variants
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
