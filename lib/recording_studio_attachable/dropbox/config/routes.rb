# frozen_string_literal: true

RecordingStudioAttachable::Dropbox::Engine.routes.draw do
  resources :recordings, only: [] do
    get "bootstrap", to: "bootstrap#show", as: :bootstrap
    get "connect", to: "oauth#new", as: :connect
    delete "connect", to: "oauth#destroy", as: :disconnect
  end

  get "oauth/callback", to: "oauth#callback", as: :oauth_callback
end
