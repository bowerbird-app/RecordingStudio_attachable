# frozen_string_literal: true

require "test_helper"
require_relative "../app/helpers/recording_studio_attachable/providers_helper"

class ProvidersHelperTest < Minitest::Test
  Entry = Struct.new(:name, :id)

  def setup
    @helper = Object.new.extend(RecordingStudioAttachable::ProvidersHelper)
  end

  def test_hash_entries_skip_nil_values_and_return_the_next_name
    entry = { "title" => nil, "name" => "Photo" }

    assert_equal "Photo", @helper.remote_file_entry_value(entry, :title, :name)
  end

  def test_object_entries_read_public_methods
    entry = Entry.new("Photo", "file-1")

    assert_equal "file-1", @helper.remote_file_entry_value(entry, :id)
  end

  def test_missing_names_return_nil
    entry = Entry.new("Photo", "file-1")

    assert_nil @helper.remote_file_entry_value(entry, :missing)
  end
end
