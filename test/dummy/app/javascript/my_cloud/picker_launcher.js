import {
  createBootstrapCache,
  openProviderAuth,
  providerNeedsAuth,
  registerUploadProviderLauncher
} from "recording_studio_attachable/provider_launchers"

const sessions = createBootstrapCache()

registerUploadProviderLauncher("my_cloud", {
  forget(bootstrapUrl) {
    sessions.forget(bootstrapUrl)
  },
  prefetch({ bootstrapUrl, start }) {
    return sessions.sessionFor(bootstrapUrl, start).promise
  },
  async launch({ controller, providerKey, bootstrapUrl, gesture, start }) {
    const session = await sessions.sessionFor(bootstrapUrl, start).promise
    const bootstrap = session.bootstrap
    if (providerNeedsAuth(bootstrap)) {
      if (gesture) openProviderAuth(controller, bootstrap, providerKey)
      return
    }

    controller.addProviderSelections(providerKey, [{ id: "file-1" }])
  }
})
