# frozen_string_literal: true

MyCloud::Engine.routes.draw do
  resources :recordings, only: [] do
    get "bootstrap", to: "bootstrap#show", as: :bootstrap
    get "connect", to: "connect#show", as: :connect
    post "connect", to: "connect#create"
    get "connected", to: "connect#complete", as: :connected
    delete "connect", to: "connect#destroy", as: :disconnect
    resources :imports, only: %i[index create]
  end
end
