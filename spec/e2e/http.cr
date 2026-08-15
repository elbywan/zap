require "spec"
require "base64"

# The HTTP stack against a real registry: the h2->h1 fallback, the
# explicit http1 protocol, the TLS verification, the registry auth, and
# the failure modes. verdaccio is HTTP/1.1-only, so the default h2 path
# exercises the ALPN fail-fast and the h1 fallback.
describe "HTTP stack against a real registry", tags: "e2e" do
  it "installs through the h2->h1 fallback against an h1-only registry" do
    project = E2E.make_project(%({"is-number":"^7.0.0"}), E2E.auth_npmrc)
    ok, output = E2E.zap(project, "install", "--frozen-lockfile=false")
    ok.should be_true, "install failed: #{output}"
    E2E.assert_installed(project, ["is-number"])
  end

  it "installs with the explicit http1 protocol" do
    project = E2E.make_project(%({"is-number":"^7.0.0"}), E2E.auth_npmrc)
    File.write(File.join(project, "package.json"),
      %({"name":"e2e","version":"1.0.0","zap":{"network_protocol":"http1"},"dependencies":{"is-number":"^7.0.0"}}))
    ok, output = E2E.zap(project, "install", "--frozen-lockfile=false")
    ok.should be_true, "install failed: #{output}"
    E2E.assert_installed(project, ["is-number"])
  end

  it "installs with the TLS verified against the CA file" do
    cert = File.expand_path("fixtures/cert.pem", __DIR__)
    project = E2E.make_project(%({"is-number":"^7.0.0"}),
      "registry=#{E2E.base_url}\nstrict-ssl=true\ncafile=#{cert}\n//127.0.0.1:#{E2E.port}/:_auth=#{Base64.strict_encode("e2euser:secret")}\n")
    ok, output = E2E.zap(project, "install", "--frozen-lockfile=false")
    ok.should be_true, "install failed: #{output}"
    E2E.assert_installed(project, ["is-number"])
  end

  it "installs with the registry authentication" do
    project = E2E.make_project(%({"is-number":"^7.0.0"}), E2E.auth_npmrc)
    ok, output = E2E.zap(project, "install", "--frozen-lockfile=false")
    ok.should be_true, "install failed: #{output}"
    E2E.assert_installed(project, ["is-number"])
  end

  it "fails with a clear error when the registry requires authentication" do
    project = E2E.make_project(%({"is-number":"^7.0.0"}), "registry=#{E2E.base_url}\nstrict-ssl=false\n")
    ok, output = E2E.zap(project, "install", "--frozen-lockfile=false")
    ok.should be_false
    output.should contain("401")
  end

  it "fails with a clear error when the registry is unreachable" do
    server = TCPServer.new("127.0.0.1", 0)
    port = server.local_address.port
    server.close
    project = E2E.make_project(%({"is-number":"^7.0.0"}), "registry=https://127.0.0.1:#{port}\nstrict-ssl=false\n")
    ok, output = E2E.zap(project, "install", "--frozen-lockfile=false")
    ok.should be_false
    output.should contain("Error")
  end
end
