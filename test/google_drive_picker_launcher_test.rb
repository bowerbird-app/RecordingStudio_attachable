# frozen_string_literal: true

require "test_helper"
require "json"
require "open3"
require "tmpdir"

class GoogleDrivePickerLauncherTest < Minitest::Test
  def test_google_drive_launcher_connects_then_chooses_on_the_same_page
    launcher_source = File.read(google_drive_launcher_path)
    upload_source = File.read(upload_controller_path)
    picker_source = File.read(image_picker_controller_path)

    assert_includes launcher_source, "prefetch({ controller, bootstrapUrl, button })"
    assert_includes launcher_source, "forget(bootstrapUrl)"
    assert_includes launcher_source, "accessTokenNearExpiry"
    refute_includes launcher_source, "Choose from Google Drive"
    refute_includes launcher_source, "showProviderContinueButton"
    assert_includes launcher_source, "if (gesture && canOpenNow(session))"
    assert_includes upload_source, "relaunchUploadProvider"
    assert_includes upload_source, "delete button.dataset.providerPrefetchBound"
    assert_includes picker_source, "relaunchUploadProvider"
    assert_includes picker_source, "delete button.dataset.providerPrefetchBound"

    skip "node is not available" unless node_available?

    stdout, stderr, status = run_node_launcher_harness
    assert status.success?, "#{stderr}\n#{stdout}"
    result = JSON.parse(stdout)
    assert_equal true, result.fetch("chooseOnReadyClick")
    assert_equal true, result.fetch("popupOnReadyAuthClick")
    assert_equal true, result.fetch("postedOauthConnectIntoPopup")
    assert_equal true, result.fetch("chooseAfterConnectOnSamePage")
    assert_equal 0, result.fetch("continueButtonsAfterConnect")
    assert_equal 2, result.fetch("bootstrapsAfterRelaunch")
    assert_equal 0, result.fetch("popupAfterConnectOnSamePage")
    assert_equal true, result.fetch("refetchedNearExpiry")
    assert_equal true, result.fetch("forbiddenPrefetchHandled")
    assert_equal true, result.fetch("forbiddenButtonDisabled")
    assert_equal false, result.fetch("forbiddenPrefetchAnnounced")
    assert_equal 0, result.fetch("unhandledRejections")
  end

  private

  def google_drive_launcher_path
    File.expand_path("../app/javascript/controllers/recording_studio_attachable/google_drive_picker_launcher.js", __dir__)
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
    Dir.mktmpdir("google-drive-launcher-test") do |dir|
      File.write(
        File.join(dir, "provider_launchers.js"),
        browser_globals_prefix + File.read(provider_launchers_path)
      )
      File.write(
        File.join(dir, "google_drive_picker_launcher.js"),
        browser_globals_prefix + File.read(google_drive_launcher_path).sub(
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
      const pickerCalls = []
      const popupCalls = []
      const formPosts = []

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
            if (type === "click") this._click = fn
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

      function installGooglePicker() {
        globalThis.window.gapi = {
          load(_name, options) { queueMicrotask(() => options.callback()) }
        }
        globalThis.window.google = {
          picker: {
            DocsView: class {
              setIncludeFolders() { return this }
              setSelectFolderEnabled() { return this }
              setMode() { return this }
            },
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
      }

      const head = {
        appendChild(script) {
          queueMicrotask(() => {
            script.dataset.loaded = "true"
            installGooglePicker()
            script._load?.()
          })
          return script
        }
      }

      globalThis.document = {
        querySelector() { return null },
        createElement(tag) {
          const node = element(tag)
          node.type = ""
          node.name = ""
          node.value = ""
          node.method = ""
          node.action = ""
          node.target = ""
          node.submit = function() {
            const fields = {}
            this.children.forEach((child) => {
              if (child.name) fields[child.name] = child.value
            })
            formPosts.push({ action: this.action, method: this.method, target: this.target, fields })
          }
          node.remove = function() {}
          node.addEventListener = (type, fn) => {
            if (type === "load") node._load = fn
            if (type === "error") node._error = fn
            if (type === "click") node._click = fn
          }
          return node
        },
        head,
        body: {
          appendChild(child) { return child }
        }
      }
      globalThis.window = globalThis
      globalThis.window.location = { origin: "https://example.test" }

      const { getUploadProviderLauncher, relaunchUploadProvider } = await import("./provider_launchers.js")
      await import("./google_drive_picker_launcher.js")
      const launcher = getUploadProviderLauncher("google_drive")

      function controller() {
        const root = element()
        const instance = {
          element: root,
          providerButtonsByKey: new Map(),
          fetchProviderBootstrap: async () => ({
            access_token: "token-1",
            expires_at: Math.floor(Date.now() / 1000) + 3600,
            api_key: "api-key",
            app_id: "app-id"
          }),
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
      await launcher.prefetch({ controller: readyController, bootstrapUrl: "/drive/ready" })
      await new Promise((resolve) => setTimeout(resolve, 0))
      pickerCalls.length = 0
      await launcher.launch({
        controller: readyController,
        providerKey: "google_drive",
        bootstrapUrl: "/drive/ready",
        gesture: true
      })
      const chooseOnReadyClick = pickerCalls.length === 1

      const authController = controller()
      authController.fetchProviderBootstrap = async () => ({
        client_id: "client-id",
        connect_url: "/google_drive/recordings/rec-1/connect?popup=1",
        oauth_connect_url: "/recording_studio_oauth/outbound/google_drive/connect",
        return_to: "/google_drive/recordings/rec-1/connected?popup=1",
        authenticity_token: "csrf-token"
      })
      await launcher.prefetch({ controller: authController, bootstrapUrl: "/drive/auth" })
      popupCalls.length = 0
      formPosts.length = 0
      await launcher.launch({
        controller: authController,
        providerKey: "google_drive",
        bootstrapUrl: "/drive/auth",
        gesture: true
      })
      const popupOnReadyAuthClick = popupCalls[0] === "about:blank"
      const postedOauthConnectIntoPopup = formPosts[0]?.action === "/recording_studio_oauth/outbound/google_drive/connect" &&
        formPosts[0]?.target === "google_drive-auth" &&
        formPosts[0]?.fields?.owner === "user" &&
        formPosts[0]?.fields?.return_to?.includes("/google_drive/recordings/rec-1/connected") &&
        formPosts[0]?.fields?.authenticity_token === "csrf-token"

      const connectThenChooseController = controller()
      const connectThenChooseButton = element("button")
      connectThenChooseButton.dataset.providerKey = "google_drive"
      connectThenChooseButton.dataset.providerLauncher = "google_drive"
      connectThenChooseButton.dataset.providerBootstrapUrl = "/drive/connect-then-choose"
      connectThenChooseController.providerButtonsByKey.set("google_drive", connectThenChooseButton)
      let connectThenChooseBootstraps = 0
      connectThenChooseController.fetchProviderBootstrap = async () => {
        connectThenChooseBootstraps += 1
        if (connectThenChooseBootstraps === 1) {
          return {
            client_id: "client-id",
            connect_url: "/google_drive/recordings/rec-1/connect?popup=1",
            oauth_connect_url: "/recording_studio_oauth/outbound/google_drive/connect",
            return_to: "/google_drive/recordings/rec-1/connected?popup=1",
            authenticity_token: "csrf-token"
          }
        }
        return {
          access_token: "token-2",
          expires_at: Math.floor(Date.now() / 1000) + 3600,
          api_key: "api-key",
          app_id: "app-id"
        }
      }
      await launcher.prefetch({
        controller: connectThenChooseController,
        bootstrapUrl: "/drive/connect-then-choose",
        button: connectThenChooseButton
      })
      await launcher.launch({
        controller: connectThenChooseController,
        providerKey: "google_drive",
        bootstrapUrl: "/drive/connect-then-choose",
        button: connectThenChooseButton,
        gesture: true
      })
      popupCalls.length = 0
      pickerCalls.length = 0
      await Promise.all([
        relaunchUploadProvider(connectThenChooseController, "google_drive"),
        relaunchUploadProvider(connectThenChooseController, "google_drive")
      ])
      await new Promise((resolve) => setTimeout(resolve, 0))
      const continueButtonsAfterConnect = connectThenChooseController.element._continueRegion?.children?.length || 0
      const popupAfterConnectOnSamePage = popupCalls.length
      const bootstrapsAfterRelaunch = connectThenChooseBootstraps
      const chooseAfterConnectOnSamePage = pickerCalls.length === 1

      let expiryFetches = 0
      const expiryController = controller()
      expiryController.fetchProviderBootstrap = async () => {
        expiryFetches += 1
        return {
          access_token: expiryFetches === 1 ? "old-token" : "new-token",
          expires_at: expiryFetches === 1 ? Math.floor(Date.now() / 1000) + 5 : Math.floor(Date.now() / 1000) + 3600,
          api_key: "api-key",
          app_id: "app-id"
        }
      }
      await launcher.prefetch({ controller: expiryController, bootstrapUrl: "/drive/expiry" })
      await new Promise((resolve) => setTimeout(resolve, 0))
      await launcher.prefetch({ controller: expiryController, bootstrapUrl: "/drive/expiry" })
      await new Promise((resolve) => setTimeout(resolve, 0))
      const refetchedNearExpiry = expiryFetches === 2

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
        bootstrapUrl: "/drive/forbidden",
        button: forbiddenButton
      })
      await new Promise((resolve) => setTimeout(resolve, 0))
      process.off("unhandledRejection", onUnhandled)
      const forbiddenPrefetchHandled = forbiddenController._bootstrapError?.status === 403
      const forbiddenButtonDisabled = forbiddenButton.disabled === true
      const forbiddenPrefetchAnnounced = forbiddenController._announced

      process.stdout.write(JSON.stringify({
        chooseOnReadyClick,
        popupOnReadyAuthClick,
        postedOauthConnectIntoPopup,
        chooseAfterConnectOnSamePage,
        continueButtonsAfterConnect,
        popupAfterConnectOnSamePage,
        bootstrapsAfterRelaunch,
        refetchedNearExpiry,
        forbiddenPrefetchHandled,
        forbiddenButtonDisabled,
        forbiddenPrefetchAnnounced,
        unhandledRejections: unhandled.length
      }))
    JS
  end
end
