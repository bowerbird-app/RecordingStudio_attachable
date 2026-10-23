# frozen_string_literal: true

require "test_helper"
require "json"
require "open3"
require "tmpdir"

class ParallelProviderPrefetchTest < Minitest::Test
  def test_disconnected_providers_prefetch_in_parallel_then_each_connects
    skip "node is not available" unless node_available?

    stdout, stderr, status = run_node_harness
    assert status.success?, "#{stderr}\n#{stdout}"
    result = JSON.parse(stdout)
    assert_equal 1, result.fetch("dropboxFetchesAfterPrefetch")
    assert_equal 1, result.fetch("driveFetchesAfterPrefetch")
    assert_equal 2, result.fetch("dropboxFetchesAfterRelaunch")
    assert_equal 2, result.fetch("driveFetchesAfterRelaunch")
    assert_equal "/dropbox/connect?popup=1", result.fetch("dropboxPopup")
    assert_equal "/drive/connect?popup=1", result.fetch("drivePopup")
    assert_equal 0, result.fetch("dropboxChooseWithoutClick")
    assert_equal 0, result.fetch("dropboxContinueAfterConnect")
    assert_equal true, result.fetch("dropboxChooseAfterConnect")
    assert_equal 0, result.fetch("driveContinueAfterConnect")
    assert_equal true, result.fetch("driveChooseAfterConnect")
  end

  private

  def node_available?
    system("node", "-v", out: File::NULL, err: File::NULL)
  end

  def run_node_harness
    Dir.mktmpdir("parallel-provider-prefetch") do |dir|
      write_module(dir, "provider_launchers.js", provider_launchers_path)
      write_module(dir, "dropbox_picker_launcher.js", dropbox_launcher_path)
      write_module(dir, "google_drive_picker_launcher.js", drive_launcher_path)
      File.write(File.join(dir, "harness.mjs"), harness_source)
      Open3.capture3("node", File.join(dir, "harness.mjs"))
    end
  end

  def write_module(dir, name, source_path)
    rewritten = File.read(source_path).sub(
      'from "controllers/recording_studio_attachable/provider_launchers"',
      'from "./provider_launchers.js"'
    )
    File.write(File.join(dir, name), "#{browser_globals_prefix}#{rewritten}")
  end

  def browser_globals_prefix
    "const window = globalThis;\nconst document = globalThis.document;\n"
  end

  def provider_launchers_path
    File.expand_path("../app/javascript/controllers/recording_studio_attachable/provider_launchers.js", __dir__)
  end

  def dropbox_launcher_path
    File.expand_path("../app/javascript/controllers/recording_studio_attachable/dropbox_picker_launcher.js", __dir__)
  end

  def drive_launcher_path
    File.expand_path("../app/javascript/controllers/recording_studio_attachable/google_drive_picker_launcher.js", __dir__)
  end

  def harness_source
    <<~JS
      const popupCalls = []
      const chooseCalls = []
      const pickerCalls = []

      function element() {
        const node = {
          dataset: {},
          children: [],
          className: "",
          textContent: "",
          setAttribute() {},
          addEventListener(type, fn) { if (type === "click") this._click = fn },
          querySelector(selector) {
            if (selector === "[data-provider-continue-region]") return this._continueRegion || null
            return null
          },
          insertAdjacentElement(_where, child) { return this.appendChild(child) },
          appendChild(child) {
            this.children.push(child)
            if (child.dataset?.providerContinueRegion) this._continueRegion = child
            return child
          },
          replaceChildren(...nodes) { this.children = nodes }
        }
        return node
      }

      const head = {
        appendChild(script) {
          queueMicrotask(() => {
            script.dataset.loaded = "true"
            globalThis.window.Dropbox = {
              choose(options) {
                chooseCalls.push(true)
                options.success([{ id: "id-1" }])
              }
            }
            globalThis.window.gapi = { load(_name, options) { queueMicrotask(() => options.callback()) } }
            globalThis.window.google = {
              picker: {
                DocsView: class { setIncludeFolders() { return this } setSelectFolderEnabled() { return this } setMode() { return this } },
                PickerBuilder: class {
                  setAppId() { return this }
                  setDeveloperKey() { return this }
                  setOAuthToken() { return this }
                  setOrigin() { return this }
                  enableFeature() { return this }
                  addView() { return this }
                  setCallback(callback) { this._callback = callback; return this }
                  build() {
                    const callback = this._callback
                    return {
                      setVisible() {
                        pickerCalls.push(true)
                        callback({ action: "picked", docs: [{ id: "doc-1" }] })
                      }
                    }
                  }
                },
                Feature: { MULTISELECT_ENABLED: "multi" },
                DocsViewMode: { LIST: "list" },
                Action: { PICKED: "picked", CANCEL: "cancel" }
              }
            }
            script._load?.()
          })
          return script
        }
      }

      globalThis.document = {
        querySelector() { return null },
        createElement(tag) {
          const node = element()
          node.addEventListener = (type, fn) => {
            if (type === "load") node._load = fn
            if (type === "click") node._click = fn
          }
          return node
        },
        head
      }
      globalThis.window = globalThis
      globalThis.window.location = { origin: "https://example.test" }

      const { getUploadProviderLauncher, relaunchUploadProvider } = await import("./provider_launchers.js")
      await import("./dropbox_picker_launcher.js")
      await import("./google_drive_picker_launcher.js")
      const dropbox = getUploadProviderLauncher("dropbox")
      const drive = getUploadProviderLauncher("google_drive")

      let dropboxFetches = 0
      let driveFetches = 0
      const shared = element()
      function makeController(launcher, key, url, fetchImpl) {
        const instance = {
          element: shared,
          providerButtonsByKey: new Map(),
          fetchProviderBootstrap: fetchImpl,
          openPopup: (href) => { popupCalls.push(href); return { focus() {} } },
          setProviderStatus() {},
          clearProviderStatus() {},
          addProviderSelections() {},
          launchClientPicker(button, { gesture = false } = {}) {
            return launcher.launch({
              controller: instance,
              providerKey: key,
              bootstrapUrl: url,
              button,
              gesture
            })
          }
        }
        const button = element()
        button.dataset.providerKey = key
        button.dataset.providerLauncher = key
        button.dataset.providerBootstrapUrl = url
        instance.providerButtonsByKey.set(key, button)
        return instance
      }

      const dropboxController = makeController(dropbox, "dropbox", "/dropbox/bootstrap", async () => {
        dropboxFetches += 1
        if (dropboxFetches === 1) return { client_id: "dropbox-key", connect_url: "/dropbox/connect?popup=1" }
        return { client_id: "dropbox-key" }
      })
      const driveController = makeController(drive, "google_drive", "/drive/bootstrap", async () => {
        driveFetches += 1
        if (driveFetches === 1) {
          return { client_id: "drive-key", api_key: "api", app_id: "1", connect_url: "/drive/connect?popup=1" }
        }
        return {
          access_token: "token-2",
          expires_at: Math.floor(Date.now() / 1000) + 3600,
          api_key: "api",
          app_id: "1"
        }
      })

      await Promise.all([
        dropbox.prefetch({ controller: dropboxController, bootstrapUrl: "/dropbox/bootstrap" }),
        drive.prefetch({ controller: driveController, bootstrapUrl: "/drive/bootstrap" })
      ])
      const dropboxFetchesAfterPrefetch = dropboxFetches
      const driveFetchesAfterPrefetch = driveFetches

      popupCalls.length = 0
      await dropbox.launch({
        controller: dropboxController,
        providerKey: "dropbox",
        bootstrapUrl: "/dropbox/bootstrap",
        button: dropboxController.providerButtonsByKey.get("dropbox"),
        gesture: true
      })
      const dropboxPopup = popupCalls[0]
      popupCalls.length = 0
      await drive.launch({
        controller: driveController,
        providerKey: "google_drive",
        bootstrapUrl: "/drive/bootstrap",
        button: driveController.providerButtonsByKey.get("google_drive"),
        gesture: true
      })
      const drivePopup = popupCalls[0]

      chooseCalls.length = 0
      pickerCalls.length = 0
      await Promise.all([
        relaunchUploadProvider(dropboxController, "dropbox"),
        relaunchUploadProvider(dropboxController, "dropbox")
      ])
      await new Promise((resolve) => queueMicrotask(resolve))
      const dropboxContinueAfterConnect = dropboxController.element._continueRegion?.children?.length || 0
      const dropboxChooseWithoutClick = chooseCalls.length
      await dropbox.launch({
        controller: dropboxController,
        providerKey: "dropbox",
        bootstrapUrl: "/dropbox/bootstrap",
        button: dropboxController.providerButtonsByKey.get("dropbox"),
        gesture: true
      })
      const dropboxChooseAfterConnect = chooseCalls.length === 1
      const dropboxFetchesAfterRelaunch = dropboxFetches

      await Promise.all([
        relaunchUploadProvider(driveController, "google_drive"),
        relaunchUploadProvider(driveController, "google_drive")
      ])
      await new Promise((resolve) => setTimeout(resolve, 0))
      const driveContinueAfterConnect = driveController.element._continueRegion?.children?.length || 0
      const driveChooseAfterConnect = pickerCalls.length === 1
      const driveFetchesAfterRelaunch = driveFetches

      process.stdout.write(JSON.stringify({
        dropboxFetchesAfterPrefetch,
        driveFetchesAfterPrefetch,
        dropboxFetchesAfterRelaunch,
        driveFetchesAfterRelaunch,
        dropboxPopup,
        drivePopup,
        dropboxChooseAfterConnect,
        dropboxChooseWithoutClick,
        dropboxContinueAfterConnect,
        driveChooseAfterConnect,
        driveContinueAfterConnect
      }))
    JS
  end
end
