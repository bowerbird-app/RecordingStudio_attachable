# frozen_string_literal: true

RecordingStudioAttachable::Engine.routes.draw do
  resources :recordings, only: [] do
    resources :attachments, only: :index, controller: "recording_attachments"
    get "attachments/upload", to: "attachment_uploads#new", as: :attachment_upload
    post "attachments", to: "attachment_uploads#create"
    post "attachments/bulk_remove", to: "attachment_lifecycle#bulk_destroy", as: :bulk_remove_attachments
  end

  get "attachments/:id", to: "attachments#show", as: :attachment
  patch "attachments/:id", to: "attachments#update"
  delete "attachments/:id", to: "attachment_lifecycle#destroy", as: :destroy_attachment
  post "attachments/:id/restore", to: "attachment_lifecycle#restore", as: :restore_attachment
  get "attachments/:id/download", to: "attachments#download", as: :download_attachment
end
