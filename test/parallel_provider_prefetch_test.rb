# frozen_string_literal: true

require "test_helper"
require "json"
require "open3"
require "tmpdir"

class ParallelProviderPrefetchTest < Minitest::Test
  def test_generic_launcher_helpers_open_connect_and_cache_bootstrap
    skip "node is not available" unless node_available?

    stdout, stderr, status = run_node_harness
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

  private

  def node_available?
    system("node", "-v", out: File::NULL, err: File::NULL)
  end

  def run_node_harness
    Dir.mktmpdir("provider-launchers") do |dir|
      File.write(File.join(dir, "provider_launchers.js"), File.read(provider_launchers_path))
      File.write(File.join(dir, "harness.mjs"), harness_source)
      Open3.capture3("node", File.join(dir, "harness.mjs"))
    end
  end

  def provider_launchers_path
    File.expand_path("../app/javascript/controllers/recording_studio_attachable/provider_launchers.js", __dir__)
  end

  def harness_source
    <<~JS
      import { createBootstrapCache, csrfToken, openProviderAuth, providerNeedsAuth } from "./provider_launchers.js"

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

      const bootstrap = {
        needs_auth: true,
        connect: {
          url: "/my_cloud/connect",
          method: "post",
          fields: { authenticity_token: "csrf-token", owner: "user" },
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
end
