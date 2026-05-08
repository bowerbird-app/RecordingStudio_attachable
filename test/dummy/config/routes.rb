Rails.application.routes.draw do
  devise_for :users

  get "/recording_studio", to: redirect("/"), as: nil
  mount RecordingStudio::Engine, at: "/recording_studio"
  mount RecordingStudioAttachable::Engine, at: "/recording_studio_attachable"

  get "setup", to: "docs#setup", as: :setup_docs
  get "config", to: "docs#configuration", as: :configuration_docs
  get "methods", to: "docs#methods_reference", as: :methods_docs
  get "plugins", to: "docs#plugins", as: :plugins_docs
  get "resizing", to: "docs#resizing", as: :resizing_docs
  get "gem_views", to: "docs#gem_views", as: :gem_views_docs
  get "recordables", to: "docs#recordables", as: :recordables_docs
  get "query", to: "docs#query", as: :query_docs
  get "recording_tree", to: "recording_trees#index", as: :recording_tree
  get "chat/demo", to: "chat_demo#show", as: :chat_demo
  post "chat/demo/messages", to: "chat_demo#create", as: :chat_demo_messages
    post "chat/demo/messages/:id/attachments", to: "chat_demo#attach_attachment", as: :chat_demo_message_attachments
    delete "chat/demo/messages/:id/attachments/:attachment_recording_id",
      to: "chat_demo#detach_attachment",
      as: :chat_demo_message_attachment
  delete "chat/demo", to: "chat_demo#destroy", as: :reset_chat_demo
  get "upload_providers/demo", to: "upload_providers#show", as: :demo_upload_provider
  post "upload_providers/demo", to: "upload_providers#create"
  resources :pages, only: %i[show edit update]

  root "home#index"
end
