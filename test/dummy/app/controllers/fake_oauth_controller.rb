# frozen_string_literal: true

require "uri"

class FakeOauthController < ApplicationController
  skip_before_action :authenticate_user!
  skip_before_action :verify_authenticity_token, only: %i[token revoke]

  def authorize
    unless FakeOauth.valid_client?(params[:client_id])
      render plain: "unknown client", status: :bad_request
      return
    end

    unless callback_path_allowed?
      render plain: "unknown redirect", status: :bad_request
      return
    end

    code = FakeOauth.issue_code(
      access_token: "fake-access-#{SecureRandom.hex(8)}",
      refresh_token: "fake-refresh-#{SecureRandom.hex(8)}",
      user_id: "acct-demo",
      email: "demo@fake-drive.test",
      code_challenge: params[:code_challenge]
    )
    redirect_to recording_studio_oauth.outbound_callback_path(code: code, state: params[:state].to_s)
  end

  def token
    status, body = FakeOauth.call(request.url, params.to_unsafe_h)
    render json: body, status: status
  end

  def revoke
    status, body = FakeOauth.call(request.url, params.to_unsafe_h)
    render json: body, status: status
  end

  private

  def callback_path_allowed?
    uri = URI.parse(params[:redirect_uri].to_s)
    return false if uri.scheme.present? && !%w[http https].include?(uri.scheme)
    return false if uri.host.present? && uri.host != request.host

    uri.path == recording_studio_oauth.outbound_callback_path
  rescue URI::InvalidURIError
    false
  end
end
