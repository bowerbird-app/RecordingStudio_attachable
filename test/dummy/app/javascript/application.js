// Configure your import map in config/importmap.rb. Read more: https://github.com/rails/importmap-rails
import "@hotwired/turbo-rails"
import "controllers"
import "recording_studio_attachable/tiptap/attachment_image_addon"
import { application } from "controllers/application"
import * as ActiveStorage from "@rails/activestorage"

ActiveStorage.start()
