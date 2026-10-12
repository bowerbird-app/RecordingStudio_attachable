# frozen_string_literal: true

require "test_helper"
require "json"
require "open3"
require "tmpdir"

class DropboxPickerLauncherTest < Minitest::Test
  def test_dropbox_launcher_prefetches_and_chooses_inside_a_click
    launcher_source = File.read(dropbox_launcher_path)
    upload_source = File.read(upload_controller_path)
    picker_source = File.read(image_picker_controller_path)

    assert_includes launcher_source, "prefetch({ controller, bootstrapUrl, button })"
    assert_includes launcher_source, "canOpenNow(session)"
    assert_includes launcher_source, "Choose from Dropbox"
    assert_includes launcher_source, "if (gesture && canOpenNow(session))"
    assert_includes launcher_source, "return openWithGesture(controller, providerKey, session.bootstrap)"
    assert_includes launcher_source, "forget(bootstrapUrl)"
    assert_includes launcher_source, "forgetSession(bootstrapUrl)"
    refute_match(/await controller\.fetchProviderBootstrap\(bootstrapUrl\).*await ensureDropboxChooserLoaded/m, launcher_source)

    assert_includes upload_source, "prefetchClientPickers()"
    assert_includes upload_source, 'button.addEventListener("pointerenter"'
    assert_includes upload_source, "launchClientPicker(button, { gesture: true })"
    assert_includes upload_source, "delete button.dataset.providerPrefetchBound"
    assert_includes upload_source, "handleProviderBootstrapError"
    assert_includes upload_source, "relaunchUploadProvider"
    assert_includes picker_source, "prefetchClientPickers()"
    assert_includes picker_source, "launchClientPicker(button, { gesture: true })"
    assert_includes picker_source, "delete button.dataset.providerPrefetchBound"
    assert_includes picker_source, "relaunchUploadProvider"
    assert_includes File.read(provider_launchers_path), "?.forget?.("
    assert_includes File.read(provider_launchers_path), "hideProviderContinueButton"
    assert_includes File.read(provider_launchers_path), "relaunchUploadProvider"

    skip "node is not available" unless node_available?

    stdout, stderr, status = run_node_launcher_harness
    assert status.success?, "#{stderr}\n#{stdout}"
    result = JSON.parse(stdout)
    assert_equal true, result.fetch("chooseOnReadyClick")
    assert_equal 0, result.fetch("chooseOnColdClick")
    assert_equal "Choose from Dropbox", result.fetch("continueLabel")
    assert_equal true, result.fetch("chooseAfterContinueClick")
    assert_equal true, result.fetch("popupOnReadyAuthClick")
    assert_equal true, result.fetch("chooseAfterConnectOnSamePage")
    assert_equal 0, result.fetch("popupAfterConnectOnSamePage")
    assert_equal "Choose from Dropbox", result.fetch("chooseAfterConnectLabel")
    assert_equal true, result.fetch("continueClearedOnDirectOpen")
    assert_equal 2, result.fetch("bootstrapsAfterRelaunch")
    assert_equal true, result.fetch("forbiddenPrefetchHandled")
    assert_equal true, result.fetch("forbiddenButtonDisabled")
    assert_equal false, result.fetch("forbiddenPrefetchAnnounced")
    assert_equal 0, result.fetch("unhandledRejections")
  end

  private

  def dropbox_launcher_path
    File.expand_path("../app/javascript/controllers/recording_studio_attachable/dropbox_picker_launcher.js", __dir__)
  end

  def upload_controller_path
    File.expand_path("../app/javascript/controllers/recording_studio_attachable/upload_controller.js", __dir__)
  end

  def image_picker_controller_path
    File.expand_path("../app/javascript/controllers/recording_studio_attachable/attachment_image_picker_controller.js", __dir__)
  end

  def provider_launchers_path
    File.expand_path("../app/javascript/controllers/recording_studio_attachable/provider_launchers.js", __dir__)
  end

  def node_available?
    system("node", "-v", out: File::NULL, err: File::NULL)
  end

  def run_node_launcher_harness
    Dir.mktmpdir("dropbox-launcher-test") do |dir|
      File.write(
        File.join(dir, "provider_launchers.js"),
        browser_globals_prefix + File.read(provider_launchers_path)
      )
      File.write(
        File.join(dir, "dropbox_picker_launcher.js"),
        browser_globals_prefix + File.read(dropbox_launcher_path).sub(
          'from "controllers/recording_studio_attachable/provider_launchers"',
          'from "./provider_launchers.js"'
        )
      )
      File.write(File.join(dir, "harness.mjs"), node_harness_source)
      Open3.capture3("node", File.join(dir, "harness.mjs"))
    end
  end

  def browser_globals_prefix
    "const window = globalThis;\nconst document = globalThis.document;\n"
  end

  def node_harness_source
    <<~JS
      const chooseCalls = []
      const popupCalls = []
      const listeners = new Map()

      function element(tag = "div") {
        const node = {
          tagName: tag.toUpperCase(),
          dataset: {},
          className: "",
          textContent: "",
          children: [],
          attributes: {},
          setAttribute(name, value) { this.attributes[name] = value },
          addEventListener(type, fn) {
            listeners.set(this, listeners.get(this) || {})
            listeners.get(this)[type] = fn
          },
          querySelector(selector) {
            if (selector === "[data-provider-continue-region]") {
              return this._continueRegion || null
            }
            if (selector === "[data-provider-status-region]") return this._statusRegion || null
            return null
          },
          insertAdjacentElement(_where, child) {
            this.appendChild(child)
          },
          appendChild(child) {
            this.children.push(child)
            if (child.dataset?.providerContinueRegion) this._continueRegion = child
            if (child.dataset?.providerStatusRegion) this._statusRegion = child
            return child
          },
          replaceChildren(...nodes) {
            this.children = nodes
          }
        }
        return node
      }

      const head = {
        appendChild(script) {
          queueMicrotask(() => {
            script.dataset.loaded = "true"
            globalThis.window.Dropbox = {
              choose(options) {
                chooseCalls.push(options)
                options.success([{ id: "id-1" }])
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
          const node = element(tag)
          node.addEventListener = (type, fn) => {
            if (type === "load") node._load = fn
            if (type === "error") node._error = fn
            if (type === "click") node._click = fn
          }
          return node
        },
        head
      }
      globalThis.window = globalThis

      const { getUploadProviderLauncher, relaunchUploadProvider } = await import("./provider_launchers.js")
      await import("./dropbox_picker_launcher.js")
      const launcher = getUploadProviderLauncher("dropbox")

      function controller() {
        const root = element()
        const instance = {
          element: root,
          providerButtonsByKey: new Map(),
          fetchProviderBootstrap: async () => ({ client_id: "app-key", provider_key: "dropbox" }),
          openPopup: (url) => { popupCalls.push(url); return { focus() {} } },
          setProviderStatus() {},
          clearProviderStatus() {},
          addProviderSelections() {},
          launchClientPicker(button, { gesture = false } = {}) {
            return launcher.launch({
              controller: instance,
              providerKey: button.dataset.providerKey,
              bootstrapUrl: button.dataset.providerBootstrapUrl,
              button,
              gesture
            })
          }
        }
        return instance
      }

      const readyController = controller()
      await launcher.prefetch({ controller: readyController, bootstrapUrl: "/dropbox/ready" })
      await new Promise((resolve) => setTimeout(resolve, 0))
      chooseCalls.length = 0
      await launcher.launch({
        controller: readyController,
        providerKey: "dropbox",
        bootstrapUrl: "/dropbox/ready",
        gesture: true
      })
      const chooseOnReadyClick = chooseCalls.length === 1

      let resolveBootstrap
      const coldController = controller()
      coldController.fetchProviderBootstrap = () => new Promise((resolve) => {
        resolveBootstrap = () => resolve({ client_id: "app-key", provider_key: "dropbox" })
      })
      chooseCalls.length = 0
      const coldLaunch = launcher.launch({
        controller: coldController,
        providerKey: "dropbox",
        bootstrapUrl: "/dropbox/cold",
        button: element("button"),
        gesture: true
      })
      const chooseOnColdClick = chooseCalls.length
      resolveBootstrap()
      await coldLaunch
      await new Promise((resolve) => queueMicrotask(resolve))
      const continueButton = coldController.element._continueRegion?.children?.[0]
      const continueLabel = continueButton?.textContent
      chooseCalls.length = 0
      await launcher.launch({
        controller: coldController,
        providerKey: "dropbox",
        bootstrapUrl: "/dropbox/cold",
        button: element("button"),
        gesture: true
      })
      const continueClearedOnDirectOpen = (coldController.element._continueRegion?.children?.length || 0) === 0 && chooseCalls.length === 1
      const chooseAfterContinueClick = chooseCalls.length === 1

      const authController = controller()
      authController.fetchProviderBootstrap = async () => ({
        client_id: "app-key",
        connect_url: "/dropbox/recordings/rec-1/connect?popup=1"
      })
      await launcher.prefetch({ controller: authController, bootstrapUrl: "/dropbox/auth" })
      popupCalls.length = 0
      await launcher.launch({
        controller: authController,
        providerKey: "dropbox",
        bootstrapUrl: "/dropbox/auth",
        gesture: true
      })
      const popupOnReadyAuthClick = popupCalls[0]?.includes("/dropbox/recordings/rec-1/connect")

      const connectThenChooseController = controller()
      const connectThenChooseButton = element("button")
      connectThenChooseButton.dataset.providerKey = "dropbox"
      connectThenChooseButton.dataset.providerLauncher = "dropbox"
      connectThenChooseButton.dataset.providerBootstrapUrl = "/dropbox/connect-then-choose"
      connectThenChooseController.providerButtonsByKey.set("dropbox", connectThenChooseButton)
      let connectThenChooseBootstraps = 0
      connectThenChooseController.fetchProviderBootstrap = async () => {
        connectThenChooseBootstraps += 1
        if (connectThenChooseBootstraps === 1) {
          return { client_id: "app-key", connect_url: "/dropbox/recordings/rec-1/connect?popup=1" }
        }
        return { client_id: "app-key", provider_key: "dropbox" }
      }
      await launcher.prefetch({
        controller: connectThenChooseController,
        bootstrapUrl: "/dropbox/connect-then-choose",
        button: connectThenChooseButton
      })
      popupCalls.length = 0
      chooseCalls.length = 0
      await launcher.launch({
        controller: connectThenChooseController,
        providerKey: "dropbox",
        bootstrapUrl: "/dropbox/connect-then-choose",
        button: connectThenChooseButton,
        gesture: true
      })
      popupCalls.length = 0
      chooseCalls.length = 0
      await Promise.all([
        relaunchUploadProvider(connectThenChooseController, "dropbox"),
        relaunchUploadProvider(connectThenChooseController, "dropbox")
      ])
      await new Promise((resolve) => queueMicrotask(resolve))
      const chooseAfterConnectButton = connectThenChooseController.element._continueRegion?.children?.[0]
      const chooseAfterConnectLabel = chooseAfterConnectButton?.textContent
      const popupAfterConnectOnSamePage = popupCalls.length
      const bootstrapsAfterRelaunch = connectThenChooseBootstraps
      chooseAfterConnectButton?._click?.({ preventDefault() {} })
      const chooseAfterConnectOnSamePage = chooseCalls.length === 1

      const forbiddenButton = element("button")
      forbiddenButton.disabled = false
      const forbiddenController = controller()
      forbiddenController.handleProviderBootstrapError = (error, button, { announce = true } = {}) => {
        if (button && error?.status === 403) button.disabled = true
        forbiddenController._bootstrapError = error
        forbiddenController._announced = announce
      }
      forbiddenController.fetchProviderBootstrap = async () => {
        const error = new Error("Forbidden")
        error.status = 403
        throw error
      }
      const unhandled = []
      const onUnhandled = (reason) => unhandled.push(String(reason))
      process.on("unhandledRejection", onUnhandled)
      await launcher.prefetch({
        controller: forbiddenController,
        bootstrapUrl: "/dropbox/forbidden",
        button: forbiddenButton
      })
      await new Promise((resolve) => setTimeout(resolve, 0))
      process.off("unhandledRejection", onUnhandled)
      const forbiddenPrefetchHandled = forbiddenController._bootstrapError?.status === 403
      const forbiddenButtonDisabled = forbiddenButton.disabled === true
      const forbiddenPrefetchAnnounced = forbiddenController._announced

      process.stdout.write(JSON.stringify({
        chooseOnReadyClick,
        chooseOnColdClick,
        continueLabel,
        chooseAfterContinueClick,
        popupOnReadyAuthClick,
        chooseAfterConnectOnSamePage,
        popupAfterConnectOnSamePage,
        chooseAfterConnectLabel,
        continueClearedOnDirectOpen,
        bootstrapsAfterRelaunch,
        forbiddenPrefetchHandled,
        forbiddenButtonDisabled,
        forbiddenPrefetchAnnounced,
        unhandledRejections: unhandled.length
      }))
    JS
  end
end
