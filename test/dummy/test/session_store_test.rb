# frozen_string_literal: true

require "test_helper"

class SessionStoreTest < ActiveSupport::TestCase
  test "provider tokens use the encrypted cookie session and upload ids are filtered from logs" do
    store = Rails.application.config.session_store
    assert_includes [ActionDispatch::Session::CookieStore, :cookie_store], store
    filtered = ActiveSupport::ParameterFilter.new(Rails.application.config.filter_parameters)
    assert_equal "[FILTERED]", filtered.filter(signed_blob_id: "secret-id", checksum: "abc")[:signed_blob_id]
    assert_equal "[FILTERED]", filtered.filter(checksum: "abc")[:checksum]
  end
end