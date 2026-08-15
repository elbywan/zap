require "spec"
require "socket"
require "http/client"
require "openssl"
require "json"
require "file_utils"

# The end-to-end harness: boots a real verdaccio registry (https,
# HTTP/1.1-only) backed by a proxy to the npm registry, generates the
# test projects, and drives the built zap binary.
#
# The scenarios live in sibling files (http.cr, install.cr, ...), each
# tagging its specs with "e2e" so the suite stays out of the default
# per-package runs. Run:
#   crystal spec spec/e2e/specs.cr --tag e2e
module E2E
  @@work : String?
  @@port : Int32 = 0
  @@base_url : String = ""
  @@verdaccio_pid : Process?

  def self.setup(work : String, port : Int32, base_url : String) : Nil
    @@work = work
    @@port = port
    @@base_url = base_url
  end

  def self.work : String
    @@work.not_nil!
  end

  def self.port : Int32
    @@port
  end

  def self.base_url : String
    @@base_url
  end

  def self.verdaccio_pid : Process?
    @@verdaccio_pid
  end

  def self.verdaccio_pid=(pid : Process?)
    @@verdaccio_pid = pid
  end

  # The built zap binary (zap.exe on Windows).
  def self.cli : String
    %w[zap.exe zap].each do |name|
      path = File.expand_path("../../packages/cli/bin/#{name}", __DIR__)
      return path if File.exists?(path)
    end
    raise "built CLI not found; run crystal projects.cr build:cli"
  end

  # The npm CLI entry, resolved through the node on the PATH so the
  # harness works identically on every OS (Crystal cannot spawn .cmd
  # batch files on Windows; node can). The bundled npm lives next to
  # node on Windows (where "npm root -g" points at an unrelated prefix),
  # so both locations are tried.
  def self.npm_cli : String
    output = IO::Memory.new
    js = <<-JS
      const cp = require("child_process");
      const fs = require("fs");
      const path = require("path");
      const candidates = [];
      try {
        const root = cp.execSync("npm root -g").toString().trim();
        candidates.push(path.join(root, "npm", "bin", "npm-cli.js"));
      } catch {}
      candidates.push(path.join(path.dirname(process.execPath), "node_modules", "npm", "bin", "npm-cli.js"));
      const found = candidates.find((c) => fs.existsSync(c));
      if (!found) {
        console.error("npm-cli.js not found; tried: " + candidates.join(", "));
        process.exit(1);
      }
      console.log(found);
      JS
    unless Process.run("node", ["-e", js], output: output, error: output).success?
      raise "node/npm is required for the end-to-end tests; node output: #{output.to_s}"
    end
    output.to_s.strip
  end

  # The registry requires authentication (access: $authenticated); every
  # happy-path scenario sends it, and dedicated specs assert the failure
  # modes.
  def self.auth_npmrc : String
    "registry=#{base_url}\nstrict-ssl=false\n//127.0.0.1:#{port}/:_auth=#{Base64.strict_encode("e2euser:secret")}\n"
  end

  # A test project directory with the given dependencies and .npmrc.
  def self.make_project(deps : String, npmrc : String) : String
    project = File.join(work, "app-#{Random.rand(100000)}")
    Dir.mkdir_p(project)
    File.write(File.join(project, "package.json"), %({"name":"e2e","version":"1.0.0","dependencies":#{deps}}))
    File.write(File.join(project, ".npmrc"), npmrc)
    project
  end

  # Runs the zap CLI in *project*; returns {success?, output}.
  def self.zap(project : String, *args : String, env : Hash(String, String)? = nil) : {Bool, String}
    output = IO::Memory.new
    status = Process.run(cli, args.to_a, chdir: project, output: output, error: output, env: env)
    {status.success?, output.to_s}
  end

  # Asserts the install actually produced the packages.
  def self.assert_installed(project : String, packages : Array(String)) : Nil
    packages.each do |pkg|
      File.exists?(File.join(project, "node_modules", pkg)).should be_true, "missing #{pkg} in node_modules"
    end
  end
end

# Boot the verdaccio once for the whole e2e run.
Spec.before_suite do
  work = File.tempname("zap-e2e")
  Dir.mkdir_p(work)

  # A free local port for the registry.
  server = TCPServer.new("127.0.0.1", 0)
  port = server.local_address.port
  server.close
  E2E.setup(work, port, "https://127.0.0.1:#{port}")

  # Install verdaccio into the work directory.
  npm_output = IO::Memory.new
  Process.run("node", [E2E.npm_cli, "init", "-y"], chdir: work, output: npm_output, error: npm_output)
  npm_output.clear
  unless Process.run("node", [E2E.npm_cli, "install", "verdaccio"], chdir: work, output: npm_output, error: npm_output).success?
    raise "failed to install verdaccio; npm output:\n#{npm_output.to_s}"
  end

  # The configuration: proxy the real npm, gate the reads behind the
  # htpasswd auth, serve https with the committed test certificate.
  cert = File.expand_path("fixtures/cert.pem", __DIR__)
  key = File.expand_path("fixtures/key.pem", __DIR__)
  File.write(File.join(work, "config.yaml"), <<-YAML)
    storage: ./storage
    web:
      enable: false
    uplinks:
      npmjs:
        url: https://registry.npmjs.org/
    packages:
      '@*/*':
        access: $authenticated
        publish: $authenticated
        proxy: npmjs
      '**':
        access: $authenticated
        publish: $authenticated
        proxy: npmjs
    https:
      key: #{key}
      cert: #{cert}
    auth:
      htpasswd:
        file: ./htpasswd
        max_users: -1
    listen:
      - https://127.0.0.1:#{port}
    log:
      type: stdout
      format: pretty
      level: warn
    YAML

  # A user for the htpasswd (bcrypt via the verdaccio dependency).
  Process.run("node", ["-e", <<-JS], chdir: work, output: Process::Redirect::Close)
    const bcrypt = require("bcryptjs");
    require("fs").writeFileSync("htpasswd", "e2euser:" + bcrypt.hashSync("secret", 10) + "\\n");
    JS

  # Start verdaccio and wait for it to accept connections.
  verdaccio = File.join(work, "node_modules", "verdaccio", "bin", "verdaccio")
  verdaccio_log = File.open(File.join(work, "verdaccio.log"), "w")
  E2E.verdaccio_pid = Process.new("node", [verdaccio, "-c", File.join(work, "config.yaml")],
    chdir: work, output: verdaccio_log, error: verdaccio_log)
  ok = false
  40.times do
    begin
      response = HTTP::Client.new("127.0.0.1", port: port, tls: true) do |client|
        client.tls?.try(&.verify_mode = OpenSSL::SSL::VerifyMode::NONE)
        client.get("/-/ping")
      end
      ok = true if response.status_code == 200
      break if ok
    rescue
    end
    sleep 500.milliseconds
  end
  raise "verdaccio did not start; log:\n#{File.read(File.join(work, "verdaccio.log"))}" unless ok
end

Spec.after_suite do
  E2E.verdaccio_pid.try(&.terminate)
  E2E.verdaccio_pid.try(&.wait)
  FileUtils.rm_rf(E2E.work)
end
