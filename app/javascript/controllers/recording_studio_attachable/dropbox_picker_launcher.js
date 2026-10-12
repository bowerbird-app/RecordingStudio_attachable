import { registerUploadProviderLauncher } from "controllers/recording_studio_attachable/provider_launchers"

let dropboxChooserPromise

function loadScript(src, attributes = {}) {
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
    Object.entries(attributes).forEach(([key, value]) => {
      script.setAttribute(key, value)
    })
    script.addEventListener("load", () => {
      script.dataset.loaded = "true"
      resolve()
    }, { once: true })
    script.addEventListener("error", () => reject(new Error(`Could not load ${src}`)), { once: true })
    document.head.appendChild(script)
  })
}

async function ensureDropboxChooserLoaded(appKey) {
  if (!dropboxChooserPromise) {
    dropboxChooserPromise = loadScript("https://www.dropbox.com/static/api/2/dropins.js", {
      id: "dropboxjs",
      "data-app-key": appKey
    }).then(() => {
      if (!window.Dropbox?.choose) {
        throw new Error("Dropbox Chooser did not load.")
      }
    })
  }

  return dropboxChooserPromise
}

function openChooser() {
  return new Promise((resolve, reject) => {
    if (!window.Dropbox?.choose) {
      reject(new Error("Dropbox Chooser is not available."))
      return
    }

    window.Dropbox.choose({
      success: (files) => {
        resolve(
          (files || [])
            .filter((file) => file?.id)
            .map((file) => ({ id: file.id }))
        )
      },
      cancel: () => resolve([]),
      linkType: "preview",
      multiselect: true,
      folderselect: false
    })
  })
}

registerUploadProviderLauncher("dropbox", {
  async launch({ controller, providerKey, bootstrapUrl }) {
    const bootstrap = await controller.fetchProviderBootstrap(bootstrapUrl)

    if (bootstrap.auth_url) {
      const popup = controller.openPopup(bootstrap.auth_url, `${providerKey}-auth`)
      if (!popup) {
        throw new Error("The sign-in popup was blocked. Allow popups and try again.")
      }

      return
    }

    controller.setProviderStatus("Opening Dropbox…")
    await ensureDropboxChooserLoaded(bootstrap.client_id)
    const selections = await openChooser()
    if (selections.length === 0) {
      controller.clearProviderStatus()
      return
    }

    controller.clearProviderStatus()
    controller.addProviderSelections(providerKey, selections)
  }
})
