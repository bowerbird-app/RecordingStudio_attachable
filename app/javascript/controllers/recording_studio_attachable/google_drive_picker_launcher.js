import { registerUploadProviderLauncher } from "controllers/recording_studio_attachable/provider_launchers"

let googlePickerPromise

function loadScript(src) {
  return new Promise((resolve, reject) => {
    const existing = document.querySelector(`script[src='${src}']`)
    if (existing) {
      if (existing.dataset.loaded === "true" || existing.readyState === "complete" || existing.readyState === "loaded") {
        resolve()
        return
      }

      existing.addEventListener("load", resolve, { once: true })
      existing.addEventListener("error", () => reject(new Error(`Could not load ${src}`)), { once: true })
      return
    }

    const script = document.createElement("script")
    script.src = src
    script.async = true
    script.defer = true
    script.addEventListener("load", () => {
      script.dataset.loaded = "true"
      resolve()
    }, { once: true })
    script.addEventListener("error", () => reject(new Error(`Could not load ${src}`)), { once: true })
    document.head.appendChild(script)
  })
}

async function ensureGooglePickerLoaded() {
  if (!googlePickerPromise) {
    googlePickerPromise = loadScript("https://apis.google.com/js/api.js").then(() => new Promise((resolve, reject) => {
      if (!window.gapi) {
        reject(new Error("Google API client did not load."))
        return
      }

      window.gapi.load("picker", {
        callback: resolve,
        onerror: () => reject(new Error("Google Picker failed to load."))
      })
    }))
  }

  return googlePickerPromise
}

function openPicker(bootstrap) {
  return new Promise((resolve, reject) => {
    if (!window.google?.picker) {
      reject(new Error("Google Picker is not available."))
      return
    }

    const docsView = new window.google.picker.DocsView()
      .setIncludeFolders(false)
      .setSelectFolderEnabled(false)
      .setMode(window.google.picker.DocsViewMode.LIST)

    const picker = new window.google.picker.PickerBuilder()
      .setAppId(String(bootstrap.app_id))
      .setDeveloperKey(bootstrap.api_key)
      .setOAuthToken(bootstrap.access_token)
      .setOrigin(window.location.origin)
      .enableFeature(window.google.picker.Feature.MULTISELECT_ENABLED)
      .addView(docsView)
      .setCallback((data) => {
        if (data.action === window.google.picker.Action.PICKED) {
          resolve(
            data.docs
              .filter((doc) => doc?.id)
              .map((doc) => ({ id: doc.id, resource_key: doc.resourceKey }))
          )
          return
        }

        if (data.action === window.google.picker.Action.CANCEL) {
          resolve([])
        }
      })
      .build()

    picker.setVisible(true)
  })
}

registerUploadProviderLauncher("google_drive", {
  async launch({ controller, providerKey, bootstrapUrl, importUrl }) {
    const bootstrap = await controller.fetchProviderBootstrap(bootstrapUrl)

    if (bootstrap.auth_url) {
      const popup = controller.openPopup(bootstrap.auth_url, `${providerKey}-auth`)
      if (!popup) {
        throw new Error("The sign-in popup was blocked. Allow popups and try again.")
      }

      return
    }

    controller.setProviderStatus("Opening Google Drive picker…")
    await ensureGooglePickerLoaded()
    const fileIds = await openPicker(bootstrap)
    if (fileIds.length === 0) {
      controller.clearProviderStatus()
      return
    }

    controller.setProviderStatus("Importing selected Google Drive files…")
    const result = await controller.submitProviderImport(importUrl || bootstrap.import_url, fileIds)
    controller.clearProviderStatus()

    if (result.redirect_path) {
      window.location.href = result.redirect_path
    }
  }
})