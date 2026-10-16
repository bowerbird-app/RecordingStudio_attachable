# frozen_string_literal: true

RecordingStudioAttachable::Engine.routes.draw do
  RecordingStudioAttachable.adapter_route_blocks.each do |route_block|
    instance_eval(&route_block)
  end

  resources :recordings, only: [] do
    resources :attachments, only: :index, controller: "recording_attachments"
    get "attachments/picker", to: "attachment_pickers#index", as: :attachment_picker
    get "attachments/upload", to: "attachment_uploads#new", as: :attachment_upload
    post "attachments/direct_uploads", to: "direct_uploads#create", as: :direct_uploads
    post "attachments", to: "attachment_uploads#create"
    post "attachments/imports", to: "attachment_imports#create", as: :attachment_imports
    post "attachments/bulk_remove", to: "attachment_lifecycle#bulk_destroy", as: :bulk_remove_attachments
    patch "attachment_collection", to: "attachment_collections#update", as: :attachment_collection
  end

  get "attachments/:id", to: "attachments#show", as: :attachment
  get "attachments/:id/file", to: "attachments#file", as: :attachment_file
  get "attachments/:id/preview/:variant_name", to: "attachments#preview", as: :attachment_preview_file
  patch "attachments/:id", to: "attachments#update"
  delete "attachments/:id", to: "attachment_lifecycle#destroy", as: :destroy_attachment
  post "attachments/:id/restore", to: "attachment_lifecycle#restore", as: :restore_attachment
  get "attachments/:id/download", to: "attachments#download", as: :download_attachment
end
