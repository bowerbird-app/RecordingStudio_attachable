# frozen_string_literal: true

require "test_helper"

class UserSessionTest < ActionDispatch::IntegrationTest
  test "a seeded user can sign in and sign out without an error" do
    user = User.find_by(email: "admin@admin.com")
    if user.blank?
      user = User.create!(
        email: "admin@admin.com",
        password: "Password",
        password_confirmation: "Password",
        name: "Avery"
      )
    end

    post user_session_path, params: { user: { email: user.email, password: "Password" } }
    assert_response :redirect

    delete destroy_user_session_path
    assert_response :redirect
    follow_redirect!
    assert_response :success
  end
end
