Rails.application.routes.draw do
  devise_for :users

  get "/recording_studio", to: redirect("/"), as: nil
  mount RecordingStudio::Engine, at: "/recording_studio"
  mount RecordingStudioAttachable::Engine, at: "/recording_studio_attachable"

  get "setup", to: "docs#setup", as: :setup_docs
  get "config", to: "docs#configuration", as: :configuration_docs
  get "methods", to: "docs#methods_reference", as: :methods_docs
  get "gem_views", to: "docs#gem_views", as: :gem_views_docs

  root "home#index"
end
