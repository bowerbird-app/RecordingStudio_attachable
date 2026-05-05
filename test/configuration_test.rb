# frozen_string_literal: true

require "test_helper"

class ConfigurationTest < Minitest::Test
  def setup
    @configuration = RecordingStudioAttachable::Configuration.new
  end

  def test_defaults_match_attachable_expectations
    assert_equal ["image/*", "application/pdf"], @configuration.allowed_content_types
    assert_equal 20, @configuration.max_file_count
    assert_equal :direct, @configuration.default_listing_scope
    assert_equal :all, @configuration.default_kind_filter
    assert_equal :blank, @configuration.layout
    assert_equal :view, @configuration.auth_role_for(:view)
    assert_equal :edit, @configuration.auth_role_for(:upload)
  end

  def test_merge_normalizes_auth_roles
    @configuration.merge!(auth_roles: { view: :viewer, upload: :editor })

    assert_equal :view, @configuration.auth_role_for(:view)
    assert_equal :edit, @configuration.auth_role_for(:upload)
  end

  def test_merge_updates_known_attributes_and_ignores_unknown_ones
    @configuration.merge!(
      max_file_size: 5.megabytes,
      max_file_count: 8,
      default_listing_scope: :subtree,
      unknown_setting: true
    )

    assert_equal 5.megabytes, @configuration.max_file_size
    assert_equal 8, @configuration.max_file_count
    assert_equal :subtree, @configuration.default_listing_scope
  end

  def test_merge_ignores_non_enumerable_inputs
    snapshot = @configuration.to_h

    @configuration.merge!(nil)

    assert_equal snapshot, @configuration.to_h
  end

  def test_allowed_content_type_supports_wildcards
    assert @configuration.allowed_content_type?("image/png")
    refute @configuration.allowed_content_type?("text/plain")
  end

  def test_allowed_content_type_accepts_blank_overrides
    assert @configuration.allowed_content_type?("text/plain", allowed_content_types: [])
  end

  def test_attachment_kind_for_uses_classifier
    assert_equal "image", @configuration.attachment_kind_for("image/jpeg")
    assert_equal "file", @configuration.attachment_kind_for("application/pdf")
  end

  def test_attachment_kind_for_accepts_custom_classifier
    classifier = ->(_content_type) { :IMAGE }

    assert_equal "image", @configuration.attachment_kind_for("text/plain", classifier: classifier)
  end

  def test_attachment_kind_enabled_normalizes_values
    assert @configuration.attachment_kind_enabled?("IMAGE", enabled_attachment_kinds: ["image"])
    refute @configuration.attachment_kind_enabled?("audio", enabled_attachment_kinds: ["image"])
  end

  def test_normalize_role_maps_aliases_and_custom_roles
    assert_equal :view, @configuration.normalize_role("Viewing")
    assert_equal :edit, @configuration.normalize_role(:editor)
    assert_equal :admin, @configuration.normalize_role(:admin)
  end

  def test_normalize_auth_roles_symbolizes_actions_and_roles
    roles = @configuration.normalize_auth_roles("view" => "viewer", upload: "Editor")

    assert_equal({ view: :view, upload: :edit }, roles)
  end

  def test_to_h_reflects_current_values
    @configuration.layout = :application
    @configuration.enabled_attachment_kinds = %i[file]

    assert_equal(
      {
        allowed_content_types: ["image/*", "application/pdf"],
        max_file_size: 25.megabytes,
        max_file_count: 20,
        enabled_attachment_kinds: %i[file],
        default_listing_scope: :direct,
        default_kind_filter: :all,
        layout: :application,
        auth_roles: @configuration.auth_roles
      },
      @configuration.to_h
    )
  end
end
