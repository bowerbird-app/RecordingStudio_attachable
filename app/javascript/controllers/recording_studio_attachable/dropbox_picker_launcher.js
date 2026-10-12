import { registerUploadProviderLauncher, showProviderContinueButton } from "controllers/recording_studio_attachable/provider_launchers"

let dropboxChooserPromise
const sessions = new Map()

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

function forgetSession(bootstrapUrl) {
  if (bootstrapUrl) sessions.delete(bootstrapUrl)
}

function sessionFor(controller, bootstrapUrl) {
  let session = sessions.get(bootstrapUrl)
  if (session?.error) {
    forgetSession(bootstrapUrl)
    session = null
  }
  if (session) return session

  session = { ready: false, bootstrap: null, error: null, promise: null }
  session.promise = controller.fetchProviderBootstrap(bootstrapUrl).then(async (bootstrap) => {
    session.bootstrap = bootstrap
    if (bootstrap.client_id) {
      const chooser = ensureDropboxChooserLoaded(bootstrap.client_id)
      if (!bootstrap.auth_url) await chooser
    }
    session.ready = true
    return session
  }).catch((error) => {
    session.error = error
    forgetSession(bootstrapUrl)
    throw error
  })
  sessions.set(bootstrapUrl, session)
  return session
}

function canOpenNow(session) {
  if (!session?.ready || session.error || !session.bootstrap) return false
  if (session.bootstrap.auth_url) return true

  return Boolean(window.Dropbox?.choose)
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

  controller.setProviderStatus("Opening Dropbox…")
  return openChooser().then((selections) => applySelections(controller, providerKey, selections))
}

function promptToChoose(controller, sourceButton, providerKey, bootstrap) {
  const label = bootstrap.auth_url ? "Continue with Dropbox" : "Choose from Dropbox"
  showProviderContinueButton(controller, sourceButton, label, () => {
    openWithGesture(controller, providerKey, bootstrap)
  })
}

registerUploadProviderLauncher("dropbox", {
  forget(bootstrapUrl) {
    forgetSession(bootstrapUrl)
  },

  prefetch({ controller, bootstrapUrl, button }) {
    if (!controller || !bootstrapUrl) return Promise.resolve()

    return sessionFor(controller, bootstrapUrl).promise.catch((error) => {
      forgetSession(bootstrapUrl)
      controller.handleProviderBootstrapError?.(error, button)
    })
  },

  async launch({ controller, providerKey, bootstrapUrl, button, gesture = false }) {
    const session = sessionFor(controller, bootstrapUrl)
    if (gesture && canOpenNow(session)) {
      return openWithGesture(controller, providerKey, session.bootstrap)
    }

    controller.setProviderStatus("Dropbox is warming up…")
    try {
      await session.promise
    } catch (error) {
      forgetSession(bootstrapUrl)
      controller.handleProviderBootstrapError?.(error, button)
      throw error
    }
    if (session.error) throw session.error

    promptToChoose(controller, button, providerKey, session.bootstrap)
  }
})
