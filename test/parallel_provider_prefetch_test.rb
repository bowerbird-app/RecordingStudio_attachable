# frozen_string_literal: true

require "test_helper"
require "json"
require "open3"
require "tmpdir"

class ParallelProviderPrefetchTest < Minitest::Test
  def test_generic_launcher_helpers_open_connect_and_cache_bootstrap
    skip "node is not available" unless node_available?

    stdout, stderr, status = run_node_harness(harness_source)
    assert status.success?, "#{stderr}\n#{stdout}"
    result = JSON.parse(stdout)
    assert_equal true, result.fetch("needsAuth")
    assert_equal true, result.fetch("openedAuth")
    assert_equal "post", result.fetch("formMethod")
    assert_equal "/my_cloud/connect", result.fetch("formAction")
    assert_equal "csrf-token", result.fetch("csrfFromFields")
    assert_equal 1, result.fetch("cacheHits")
    assert_equal "/fallback", result.fetch("fallbackUrl")
  end

  def test_connected_my_cloud_bootstrap_launches_import
    skip "node is not available" unless node_available?

    stdout, stderr, status = run_node_harness(connected_picker_harness_source, copy_dummy_picker: true)
    assert status.success?, "#{stderr}\n#{stdout}"
    result = JSON.parse(stdout)
    assert_equal false, result.fetch("needsAuth")
    assert_equal 0, result.fetch("submittedCount")
    assert_equal "my_cloud", result.fetch("providerKey")
    assert_equal [{ "id" => "file-1" }], result.fetch("selections")
  end

  private

  def node_available?
    system("node", "-v", out: File::NULL, err: File::NULL)
  end

  def run_node_harness(source, copy_dummy_picker: false)
    Dir.mktmpdir("provider-launchers") do |dir|
      File.write(File.join(dir, "provider_launchers.js"), File.read(provider_launchers_path))
      if copy_dummy_picker
        picker = File.read(dummy_picker_path).sub(
          'from "recording_studio_attachable/provider_launchers"',
          'from "./provider_launchers.js"'
        )
        File.write(File.join(dir, "picker_launcher.js"), picker)
      end
      File.write(File.join(dir, "harness.mjs"), source)
      Open3.capture3("node", File.join(dir, "harness.mjs"))
    end
  end

  def provider_launchers_path
    File.expand_path("../app/javascript/controllers/recording_studio_attachable/provider_launchers.js", __dir__)
  end

  def dummy_picker_path
    File.expand_path("dummy/app/javascript/my_cloud/picker_launcher.js", __dir__)
  end

  def document_stub_js
    <<~JS
      const submitted = []
      const assigned = []
      globalThis.window = globalThis
      globalThis.document = {
        querySelector() { return { content: "meta-csrf" } },
        createElement(tag) {
          if (tag === "form") {
            const form = {
              method: "",
              action: "",
              target: "",
              children: [],
              appendChild(child) { this.children.push(child) },
              submit() { submitted.push({ method: this.method, action: this.action, fields: Object.fromEntries(this.children.map((c) => [c.name, c.value])) }) },
              remove() {}
            }
            return form
          }
          return { type: "", name: "", value: "" }
        },
        body: { appendChild() {}, }
      }
      globalThis.window.location = { assign(url) { assigned.push(url) } }
    JS
  end

  def harness_source
    <<~JS
      import { createBootstrapCache, csrfToken, openProviderAuth, providerNeedsAuth } from "./provider_launchers.js"

      #{document_stub_js}

      const bootstrap = {
        needs_auth: true,
        connect: {
          url: "/my_cloud/connect",
          method: "post",
          fields: { authenticity_token: "csrf-token" },
          fallback_url: "/fallback"
        }
      }

      const cache = createBootstrapCache()
      const session = cache.sessionFor("/bootstrap", () => bootstrap)
      await session.promise
      const again = cache.sessionFor("/bootstrap", () => { throw new Error("should use cache") })
      const cacheHits = again === session ? 1 : 0

      const controller = {
        openPopup() { return { name: "popup" } },
        csrfToken() { return "controller-csrf" }
      }

      const openedAuth = openProviderAuth(controller, bootstrap, "my_cloud")
      const blockedController = { openPopup() { return null }, csrfToken() { return "" } }
      openProviderAuth(blockedController, bootstrap, "my_cloud")

      console.log(JSON.stringify({
        needsAuth: providerNeedsAuth(bootstrap),
        openedAuth,
        formMethod: submitted[0]?.method,
        formAction: submitted[0]?.action,
        csrfFromFields: csrfToken(controller, bootstrap),
        cacheHits,
        fallbackUrl: assigned[0]
      }))
    JS
  end

  def connected_picker_harness_source
    <<~JS
      import { getUploadProviderLauncher, providerNeedsAuth } from "./provider_launchers.js"
      import "./picker_launcher.js"

      #{document_stub_js}

      const bootstrap = {
        needs_auth: false,
        connect: {
          url: "/my_cloud/connect",
          method: "post",
          fields: { authenticity_token: "csrf-token" },
          fallback_url: "/fallback"
        }
      }

      const selections = []
      const controller = {
        addProviderSelections(providerKey, files) { selections.push({ providerKey, files }) },
        openPopup() { return { name: "popup" } }
      }

      const launcher = getUploadProviderLauncher("my_cloud")
      await launcher.launch({
        controller,
        providerKey: "my_cloud",
        bootstrapUrl: "/bootstrap",
        gesture: true,
        start: () => bootstrap
      })

      console.log(JSON.stringify({
        needsAuth: providerNeedsAuth(bootstrap),
        submittedCount: submitted.length,
        providerKey: selections[0]?.providerKey,
        selections: selections[0]?.files
      }))
    JS
  end
end
