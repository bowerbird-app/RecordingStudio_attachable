# frozen_string_literal: true

require "test_helper"

class UserTest < ActiveSupport::TestCase
  test "a persisted user can be saved without raising" do
    user = User.create!(
      email: "user-#{SecureRandom.hex(4)}@example.com",
      password: "Password123!",
      password_confirmation: "Password123!",
      name: "Rememberable"
    )

    assert_nothing_raised { user.forget_me! }
  end
end
