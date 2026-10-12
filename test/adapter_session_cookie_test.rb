# frozen_string_literal: true

require "test_helper"

class AdapterSessionCookieTest < Minitest::Test
  def test_raise_if_overflow_allows_a_small_session
    RecordingStudioAttachable::Adapter::SessionCookie.raise_if_overflow!({ "a" => "b" })
  end

  def test_raise_if_overflow_raises_when_the_encoded_session_exceeds_the_cookie_budget
    session = { "tokens" => "x" * (RecordingStudioAttachable::Adapter::SessionCookie::COOKIE_BUDGET + 10) }

    error = assert_raises(ActionDispatch::Cookies::CookieOverflow) do
      RecordingStudioAttachable::Adapter::SessionCookie.raise_if_overflow!(session)
    end

    assert_equal RecordingStudioAttachable::Adapter::SessionCookie.overflow_message, error.message
  end
end
