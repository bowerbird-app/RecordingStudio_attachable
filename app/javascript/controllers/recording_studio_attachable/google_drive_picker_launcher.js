import { registerUploadProviderLauncher, showProviderContinueButton } from "controllers/recording_studio_attachable/provider_launchers"

let googlePickerPromise
const sessions = new Map()

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

function sessionFor(controller, bootstrapUrl) {
  let session = sessions.get(bootstrapUrl)
  if (session) return session

  session = { ready: false, bootstrap: null, error: null, promise: null }
  session.promise = controller.fetchProviderBootstrap(bootstrapUrl).then(async (bootstrap) => {
    session.bootstrap = bootstrap
    const picker = ensureGooglePickerLoaded()
    if (!bootstrap.auth_url) await picker
    session.ready = true
    return session
  }).catch((error) => {
    session.error = error
    throw error
  })
  sessions.set(bootstrapUrl, session)
  return session
}

function canOpenNow(session) {
  if (!session?.ready || session.error || !session.bootstrap) return false
  if (session.bootstrap.auth_url) return true

  return Boolean(window.google?.picker)
}

async function applySelections(controller, providerKey, selections) {
  if (selections.length === 0) {
    controller.clearProviderStatus()
    return
  }

  controller.clearProviderStatus()
  controller.addProviderSelections(providerKey, selections)
}

function openWithGesture(controller, providerKey, bootstrap) {
  if (bootstrap.auth_url) {
    const popup = controller.openPopup(bootstrap.auth_url, `${providerKey}-auth`)
    if (!popup) {
      throw new Error("The sign-in popup was blocked. Allow popups and try again.")
    }

    return
  }

  controller.setProviderStatus("Opening Google Drive picker…")
  return openPicker(bootstrap).then((selections) => applySelections(controller, providerKey, selections))
}

function promptToChoose(controller, sourceButton, providerKey, bootstrap) {
  const label = bootstrap.auth_url ? "Continue with Google Drive" : "Choose from Google Drive"
  showProviderContinueButton(controller, sourceButton, label, () => {
    openWithGesture(controller, providerKey, bootstrap)
  })
}

registerUploadProviderLauncher("google_drive", {
  prefetch({ controller, bootstrapUrl }) {
    if (!controller || !bootstrapUrl) return

    return sessionFor(controller, bootstrapUrl)
  },

  async launch({ controller, providerKey, bootstrapUrl, button, gesture = false }) {
    const session = sessionFor(controller, bootstrapUrl)
    if (gesture && canOpenNow(session)) {
      return openWithGesture(controller, providerKey, session.bootstrap)
    }

    controller.setProviderStatus("Google Drive is warming up…")
    await session.promise
    if (session.error) throw session.error

    promptToChoose(controller, button, providerKey, session.bootstrap)
  }
})
