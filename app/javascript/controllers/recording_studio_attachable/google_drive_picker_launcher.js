import { hideProviderContinueButton, registerUploadProviderLauncher } from "controllers/recording_studio_attachable/provider_launchers"

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

const ACCESS_TOKEN_REFRESH_SKEW_SECONDS = 30

function forgetSession(bootstrapUrl) {
  if (bootstrapUrl) sessions.delete(bootstrapUrl)
}

function accessTokenNearExpiry(bootstrap) {
  if (!bootstrap?.access_token) return false

  const expiresAt = Number(bootstrap.expires_at)
  if (!Number.isFinite(expiresAt) || expiresAt <= 0) return false

  return expiresAt <= (Date.now() / 1000) + ACCESS_TOKEN_REFRESH_SKEW_SECONDS
}

function sessionFor(controller, bootstrapUrl) {
  let session = sessions.get(bootstrapUrl)
  if (session?.error || accessTokenNearExpiry(session?.bootstrap)) {
    forgetSession(bootstrapUrl)
    session = null
  }
  if (session) return session

  session = { ready: false, bootstrap: null, error: null, promise: null }
  session.promise = controller.fetchProviderBootstrap(bootstrapUrl).then(async (bootstrap) => {
    session.bootstrap = bootstrap
    const picker = ensureGooglePickerLoaded()
    if (!needsAuth(bootstrap)) await picker
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

function needsAuth(bootstrap) {
  return Boolean(bootstrap?.oauth_connect_url || bootstrap?.connect_url || bootstrap?.auth_url)
}

function csrfToken(controller, bootstrap) {
  if (bootstrap?.authenticity_token) return bootstrap.authenticity_token
  if (typeof controller.csrfToken === "function") return controller.csrfToken()

  return document.querySelector("meta[name='csrf-token']")?.content || ""
}

function postOauthConnectIntoPopup(controller, bootstrap, popupName) {
  const form = document.createElement("form")
  form.method = "post"
  form.action = bootstrap.oauth_connect_url
  form.target = popupName

  const fields = {
    authenticity_token: csrfToken(controller, bootstrap),
    owner: "user",
    return_to: bootstrap.return_to || ""
  }
  Object.entries(fields).forEach(([name, value]) => {
    const input = document.createElement("input")
    input.type = "hidden"
    input.name = name
    input.value = value
    form.appendChild(input)
  })

  document.body.appendChild(form)
  form.submit()
  form.remove()
}

function canOpenNow(session) {
  if (!session?.ready || session.error || !session.bootstrap) return false
  if (needsAuth(session.bootstrap)) return true

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

function openPickerNow(controller, providerKey, bootstrap) {
  hideProviderContinueButton(controller)
  controller.setProviderStatus("Opening Google Drive picker…")
  return openPicker(bootstrap).then((selections) => applySelections(controller, providerKey, selections))
}

function openWithGesture(controller, providerKey, bootstrap) {
  hideProviderContinueButton(controller)
  const popupName = `${providerKey}-auth`
  if (bootstrap.oauth_connect_url) {
    const popup = controller.openPopup("about:blank", popupName)
    if (!popup) {
      throw new Error("The sign-in popup was blocked. Allow popups and try again.")
    }

    postOauthConnectIntoPopup(controller, bootstrap, popupName)
    return
  }

  const authUrl = bootstrap.connect_url || bootstrap.auth_url
  if (authUrl) {
    const popup = controller.openPopup(authUrl, popupName)
    if (!popup) {
      throw new Error("The sign-in popup was blocked. Allow popups and try again.")
    }

    return
  }

  return openPickerNow(controller, providerKey, bootstrap)
}

registerUploadProviderLauncher("google_drive", {
  forget(bootstrapUrl) {
    forgetSession(bootstrapUrl)
  },

  prefetch({ controller, bootstrapUrl, button }) {
    if (!controller || !bootstrapUrl) return Promise.resolve()

    return sessionFor(controller, bootstrapUrl).promise.catch((error) => {
      forgetSession(bootstrapUrl)
      controller.handleProviderBootstrapError?.(error, button, { announce: false })
    })
  },

  async launch({ controller, providerKey, bootstrapUrl, button, gesture = false }) {
    hideProviderContinueButton(controller)
    const session = sessionFor(controller, bootstrapUrl)
    if (gesture && canOpenNow(session)) {
      return openWithGesture(controller, providerKey, session.bootstrap)
    }

    controller.setProviderStatus("Google Drive is warming up…")
    try {
      await session.promise
    } catch (error) {
      forgetSession(bootstrapUrl)
      controller.handleProviderBootstrapError?.(error, button)
      throw error
    }
    if (session.error) throw session.error

    if (needsAuth(session.bootstrap)) {
      controller.clearProviderStatus()
      return
    }

    return openPickerNow(controller, providerKey, session.bootstrap)
  }
})
