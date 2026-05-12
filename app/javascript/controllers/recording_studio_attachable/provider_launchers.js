const uploadProviderLaunchers = new Map()

export function registerUploadProviderLauncher(name, launcher) {
  if (!name || !launcher) return

  uploadProviderLaunchers.set(String(name), launcher)
}

export function getUploadProviderLauncher(name) {
  return uploadProviderLaunchers.get(String(name))
}

if (typeof window !== "undefined") {
  window.RecordingStudioAttachableUploadProviders = {
    register: registerUploadProviderLauncher,
    get: getUploadProviderLauncher
  }
}