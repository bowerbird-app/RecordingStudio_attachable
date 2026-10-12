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

if (typeof window !== "undefined") {
  window.RecordingStudioAttachableUploadProviders = {
    register: registerUploadProviderLauncher,
    get: getUploadProviderLauncher
  }
}
