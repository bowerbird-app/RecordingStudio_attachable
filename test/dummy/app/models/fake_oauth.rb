# frozen_string_literal: true

require "base64"
require "digest"

class FakeOauth
  CLIENT_ID = "dummy-fake-drive"
  CLIENT_SECRET = "dummy-fake-drive-secret"
  FAIL_REFRESH = "fail-refresh"
  SCOPE = "https://www.googleapis.com/auth/drive"

  class << self
    def call(url, params)
      if url.to_s.include?("revoke")
        [200, {}]
      elsif params["grant_type"] == "refresh_token"
        refresh(params)
      else
        redeem(params)
      end
    end

    def issue_code(access_token:, refresh_token:, user_id:, email:, expires_in: 3600, scope: SCOPE,
                   code_challenge: nil)
      code = SecureRandom.urlsafe_base64(32)
      store_code(
        code,
        {
          "access_token" => access_token,
          "refresh_token" => refresh_token,
          "user_id" => user_id,
          "email" => email,
          "expires_in" => expires_in,
          "scope" => scope
        },
        code_challenge
      )
      code
    end

    def valid_client?(client_id)
      client_id.to_s == CLIENT_ID
    end

    def reset!
      issued_codes.clear
    end

    private

    def redeem(params)
      return [401, { "error" => "invalid_client" }] unless credentials_match?(params)

      entry = take_code(params["code"].to_s)
      return [400, { "error" => "invalid_grant" }] if entry.nil?
      return [400, { "error" => "invalid_grant" }] unless verifier_matches?(params["code_verifier"], entry[:challenge])

      [200, entry[:payload]]
    end

    def refresh(params)
      return [401, { "error" => "invalid_client" }] unless credentials_match?(params)
      return [400, { "error" => "invalid_grant" }] if params["refresh_token"].to_s == FAIL_REFRESH

      [
        200,
        {
          "access_token" => "refreshed-access-#{SecureRandom.hex(8)}",
          "refresh_token" => params["refresh_token"].to_s,
          "expires_in" => 3600,
          "scope" => SCOPE
        }
      ]
    end

    def credentials_match?(params)
      params["client_id"].to_s == CLIENT_ID && params["client_secret"].to_s == CLIENT_SECRET
    end

    def verifier_matches?(verifier, challenge)
      computed = Base64.urlsafe_encode64(Digest::SHA256.digest(verifier.to_s), padding: false)
      computed == challenge.to_s
    end

    def store_code(code, payload, challenge)
      issued_codes[code] = { payload: payload, challenge: challenge.to_s }
    end

    def take_code(code)
      issued_codes.delete(code)
    end

    def issued_codes
      @issued_codes ||= {}
    end
  end
end
