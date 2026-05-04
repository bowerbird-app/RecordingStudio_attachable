# frozen_string_literal: true

require "test_helper"

class ConfigurationTest < Minitest::Test
  def setup
    @configuration = RecordingStudioAttachable::Configuration.new
  end

  def test_defaults_match_attachable_expectations
    assert_equal ["image/*", "application/pdf"], @configuration.allowed_content_types
    assert_equal :direct, @configuration.default_listing_scope
    assert_equal :all, @configuration.default_kind_filter
    assert_equal :children_only, @configuration.placement
    assert_equal :view, @configuration.auth_role_for(:view)
    assert_equal :edit, @configuration.auth_role_for(:upload)
  end

  def test_merge_normalizes_auth_roles
    @configuration.merge!(auth_roles: { view: :viewer, upload: :editor })

    assert_equal :view, @configuration.auth_role_for(:view)
    assert_equal :edit, @configuration.auth_role_for(:upload)
  end

  def test_allowed_content_type_supports_wildcards
    assert @configuration.allowed_content_type?("image/png")
    refute @configuration.allowed_content_type?("text/plain")
  end

  def test_attachment_kind_for_uses_classifier
    assert_equal "image", @configuration.attachment_kind_for("image/jpeg")
    assert_equal "file", @configuration.attachment_kind_for("application/pdf")
  end
end
