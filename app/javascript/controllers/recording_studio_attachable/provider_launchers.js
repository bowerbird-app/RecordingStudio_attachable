const uploadProviderLaunchers = new Map()
const launcherChangeListeners = new Set()

export function registerUploadProviderLauncher(name, launcher) {
  if (!name || !launcher) return

  uploadProviderLaunchers.set(String(name), launcher)
  launcherChangeListeners.forEach((listener) => listener(String(name)))
}

export function onUploadProviderLaunchersChanged(listener) {
  launcherChangeListeners.add(listener)
  return () => launcherChangeListeners.delete(listener)
}

export function getUploadProviderLauncher(name) {
  return uploadProviderLaunchers.get(String(name))
}

export function hideProviderContinueButton(controller) {
  const region = controller?.element?.querySelector("[data-provider-continue-region]")
  if (region) region.replaceChildren()
}

export function relaunchUploadProvider(controller, providerKey) {
  const button = controller?.providerButtonsByKey?.get(providerKey)
  if (!button) return

  controller.providerRelaunchInFlight ||= new Set()
  if (controller.providerRelaunchInFlight.has(providerKey)) return

  controller.providerRelaunchInFlight.add(providerKey)
  getUploadProviderLauncher(button.dataset.providerLauncher)?.forget?.(button.dataset.providerBootstrapUrl)
  return Promise.resolve(controller.launchClientPicker(button, { gesture: false })).finally(() => {
    controller.providerRelaunchInFlight.delete(providerKey)
  })
}

export function showProviderContinueButton(controller, sourceButton, label, onClick) {
  if (!controller?.element) return

  controller.clearProviderStatus?.()

  let region = controller.element.querySelector("[data-provider-continue-region]")
  if (!region) {
    region = document.createElement("div")
    region.dataset.providerContinueRegion = "true"
    region.className = "mt-3 flex justify-center"
    const status = controller.element.querySelector("[data-provider-status-region]")
    if (status) {
      status.insertAdjacentElement("afterend", region)
    } else {
      controller.element.appendChild(region)
    }
  }

  region.replaceChildren()
  const button = document.createElement("button")
  button.type = "button"
  button.textContent = label
  button.className = sourceButton?.className || "text-sm underline"
  button.addEventListener("click", (event) => {
    event.preventDefault()
    region.replaceChildren()
    onClick()
  })
  region.appendChild(button)
}

export function loadScript(src) {
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

export function createBootstrapCache() {
  const sessions = new Map()

  return {
    forget(bootstrapUrl) {
      if (bootstrapUrl) sessions.delete(bootstrapUrl)
    },
    get(bootstrapUrl) {
      return sessions.get(bootstrapUrl)
    },
    sessionFor(bootstrapUrl, start) {
      let session = sessions.get(bootstrapUrl)
      if (session?.error) {
        sessions.delete(bootstrapUrl)
        session = null
      }
      if (session) return session

      session = { ready: false, bootstrap: null, error: null, promise: null }
      session.promise = Promise.resolve(start()).then((bootstrap) => {
        session.bootstrap = bootstrap
        session.ready = true
        return session
      }).catch((error) => {
        session.error = error
        sessions.delete(bootstrapUrl)
        throw error
      })
      sessions.set(bootstrapUrl, session)
      return session
    }
  }
}

export function providerNeedsAuth(bootstrap) {
  return Boolean(bootstrap?.needs_auth || bootstrap?.connect)
}

export function csrfToken(controller, bootstrap) {
  const fields = bootstrap?.connect?.fields
  if (fields?.authenticity_token) return fields.authenticity_token
  if (bootstrap?.authenticity_token) return bootstrap.authenticity_token
  if (typeof controller?.csrfToken === "function") return controller.csrfToken()

  return document.querySelector("meta[name='csrf-token']")?.content || ""
}

export function openProviderAuth(controller, bootstrap, providerKey) {
  const connect = bootstrap?.connect
  if (!connect?.url) return false

  const popupName = `${providerKey}-auth`
  const popup = controller.openPopup("about:blank", popupName)
  if (!popup) {
    if (connect.fallback_url) {
      window.location.assign(connect.fallback_url)
      return true
    }

    throw new Error("The sign-in popup was blocked. Allow popups and try again.")
  }

  postConnectIntoPopup(connect, popupName, csrfToken(controller, bootstrap))
  return true
}

function postConnectIntoPopup(connect, popupName, token) {
  const form = document.createElement("form")
  form.method = (connect.method || "post").toLowerCase()
  form.action = connect.url
  form.target = popupName

  const fields = { ...(connect.fields || {}) }
  if (token && fields.authenticity_token == null) fields.authenticity_token = token

  Object.entries(fields).forEach(([name, value]) => {
    const input = document.createElement("input")
    input.type = "hidden"
    input.name = name
    input.value = value == null ? "" : String(value)
    form.appendChild(input)
  })

  document.body.appendChild(form)
  form.submit()
  form.remove()
}

if (typeof window !== "undefined") {
  window.RecordingStudioAttachableUploadProviders = {
    register: registerUploadProviderLauncher,
    get: getUploadProviderLauncher,
    loadScript,
    createBootstrapCache,
    providerNeedsAuth,
    openProviderAuth,
    csrfToken
  }
}
