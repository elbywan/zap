require "spec"
require "http/server"
require "compress/gzip"
require "digest/sha1"
require "json"
require "file_utils"
require "random/secure"
require "semver"
require "../../../install/install"
require "../../../install/config"
require "core/config"
require "reporter/null"

# End-to-end install harness: spins up a minimal in-memory npm registry and
# runs real installs against it, so tests can exercise real-world repository
# shapes (peer deps, aliases, scoped packages, overrides, workspaces…) without
# touching the network.
module Zap
  def self.print_banner; end
end

alias It = Zap::Integration

module Zap::Integration
  alias Json = JSON::Any

  def self.json(value : String) : Json
    Json.new(value)
  end

  def self.json(value : Int32 | Int64) : Json
    Json.new(value.to_i64)
  end

  def self.json(value : Bool) : Json
    Json.new(value)
  end

  def self.json(value : Array(String)) : Json
    Json.new(value.map { |v| Json.new(v) })
  end

  def self.json(value : Hash(String, String)) : Json
    Json.new(value.transform_values { |v| Json.new(v) })
  end

  def self.json(value : Hash(String, Json)) : Json
    Json.new(value)
  end

  # Builds a package.json manifest hash with the usual convenience fields.
  def self.pkg(
    name : String,
    version : String,
    *,
    main : String = "index.js",
    dependencies : Hash(String, String) = {} of String => String,
    dev_dependencies : Hash(String, String) = {} of String => String,
    peer_dependencies : Hash(String, String) = {} of String => String,
    optional_dependencies : Hash(String, String) = {} of String => String,
    os : Array(String)? = nil,
    cpu : Array(String)? = nil,
    engines : Hash(String, String)? = nil,
    scripts : Hash(String, String) = {} of String => String,
    bin : String? = nil,
    extra : Hash(String, Json) = {} of String => Json,
  ) : Hash(String, Json)
    manifest = {
      "name"    => json(name),
      "version" => json(version),
      "main"    => json(main),
    }
    manifest["dependencies"] = json(dependencies) unless dependencies.empty?
    manifest["devDependencies"] = json(dev_dependencies) unless dev_dependencies.empty?
    manifest["peerDependencies"] = json(peer_dependencies) unless peer_dependencies.empty?
    manifest["optionalDependencies"] = json(optional_dependencies) unless optional_dependencies.empty?
    manifest["scripts"] = json(scripts) unless scripts.empty?
    manifest["os"] = Json.new(os.not_nil!.map { |v| Json.new(v) }) if os
    manifest["cpu"] = Json.new(cpu.not_nil!.map { |v| Json.new(v) }) if cpu
    manifest["engines"] = Json.new(engines.not_nil!.transform_values { |v| Json.new(v) }) if engines
    manifest["bin"] = json(bin) if bin
    manifest.merge!(extra)
    manifest
  end

  # A minimal npm-compatible registry, served from memory.
  class Registry
    getter port : Int32
    getter base_url : String

    @server : HTTP::Server
    @versions = {} of String => Hash(String, Hash(String, Json))
    @tarballs = {} of String => Hash(String, Bytes)
    @times = {} of String => Hash(String, String)
    @closed = false

    def initialize
      @server = HTTP::Server.new do |ctx|
        handle(ctx)
      end
      @server.bind_tcp("127.0.0.1", 0)
      @port = @server.addresses.first.as(Socket::IPAddress).port
      @base_url = "http://127.0.0.1:#{@port}"
      start
    end

    def start : Nil
      spawn do
        begin
          @server.listen
        rescue ex
          puts "FIXTURE REGISTRY LISTEN CRASHED: #{ex.class}: #{ex.message}"
        end
      end
      until ready?
        Fiber.yield
      end
    end

    def stop : Nil
      unless @closed
        @server.close
        @closed = true
      end
    end

    # Registers a package version. `files` are stored at the package root
    # (e.g. "index.js", "lib/util.js"); the manifest is written as
    # package.json and a tarball is built with the npm "package/" layout.
    def add(name : String, version : String, manifest : Hash(String, Json), files : Hash(String, String), *, published_at : Time? = nil) : Nil
      package_json = manifest.merge({"name" => Zap::Integration.json(name), "version" => Zap::Integration.json(version)})
      tarball = build_tarball(package_json, files)
      shasum = Digest::SHA1.hexdigest(tarball)

      if published_at
        (@times[name] ||= {} of String => String)[version] = published_at.to_utc.to_s("%Y-%m-%dT%H:%M:%S.%LZ")
      end

      dist : Hash(String, Json) = {
        "tarball" => Zap::Integration.json("#{base_url}/#{name}/-/#{File.basename(name)}-#{version}.tgz"),
        "shasum"  => Zap::Integration.json(shasum),
      }
      version_manifest = package_json.dup
      version_manifest["dist"] = Zap::Integration.json(dist)

      (@versions[name] ||= {} of String => Hash(String, Json))[version] = version_manifest
      (@tarballs[name] ||= {} of String => Bytes)[version] = tarball
    end

    # Registers metadata whose dist.shasum does not match the served tarball.
    def add_with_wrong_shasum(name : String, version : String, manifest : Hash(String, Json), files : Hash(String, String)) : Nil
      package_json = manifest.merge({"name" => Zap::Integration.json(name), "version" => Zap::Integration.json(version)})
      tarball = build_tarball(package_json, files)

      dist : Hash(String, Json) = {
        "tarball" => Zap::Integration.json("#{base_url}/#{name}/-/#{File.basename(name)}-#{version}.tgz"),
        "shasum"  => Zap::Integration.json("0" * 40),
      }
      version_manifest = package_json.dup
      version_manifest["dist"] = Zap::Integration.json(dist)

      (@versions[name] ||= {} of String => Hash(String, Json))[version] = version_manifest
      (@tarballs[name] ||= {} of String => Bytes)[version] = tarball
    end

    # Registers a package whose tarball is garbage but whose metadata shasum
    # matches it, so the download passes the integrity check and the unpack
    # fails.
    def add_garbage_tarball(name : String, version : String, manifest : Hash(String, Json)) : Nil
      package_json = manifest.merge({"name" => Zap::Integration.json(name), "version" => Zap::Integration.json(version)})
      tarball = Bytes.new(64, 0xAB)

      dist : Hash(String, Json) = {
        "tarball" => Zap::Integration.json("#{base_url}/#{name}/-/#{File.basename(name)}-#{version}.tgz"),
        "shasum"  => Zap::Integration.json(Digest::SHA1.hexdigest(tarball)),
      }
      version_manifest = package_json.dup
      version_manifest["dist"] = Zap::Integration.json(dist)

      (@versions[name] ||= {} of String => Hash(String, Json))[version] = version_manifest
      (@tarballs[name] ||= {} of String => Bytes)[version] = tarball
    end

    private def ready? : Bool
      socket = TCPSocket.new("127.0.0.1", @port)
      socket.close
      true
    rescue
      false
    end

    private def handle(ctx : HTTP::Server::Context) : Nil
      path = URI.decode(ctx.request.path.not_nil!)
      parts = path.strip('/').split('/')
      if dash = parts.index("-")
        # /name.../-/file.tgz -> tarball (name may be scoped: @scope/pkg/-/pkg-1.0.0.tgz)
        name = parts[0...dash].join("/")
        file = parts[dash + 1]?
        version = file.try &.gsub(/^#{File.basename(name)}-/, "").gsub(/\.tgz$/, "")
        if version && (versions = @tarballs[name]?) && (tarball = versions[version]?)
          ctx.response.content_type = "application/octet-stream"
          ctx.response.write(tarball)
        else
          ctx.response.status_code = 404
        end
      else
        # /name (possibly @scope/name) -> packument
        name = parts.join("/")
        if versions = @versions[name]?
          ctx.response.content_type = "application/json"
          ctx.response.print(packument(name, versions))
        else
          ctx.response.status_code = 404
        end
      end
    end

    private def packument(name : String, versions : Hash(String, Hash(String, Json))) : String
      latest = versions.keys.max_by { |v| Semver::Version.parse(v) }
      dist_tags : Hash(String, Json) = {"latest" => Zap::Integration.json(latest)}
      packument = {
        "dist-tags" => Zap::Integration.json(dist_tags),
        "versions"  => Json.new(versions.transform_values { |v| Json.new(v) }),
      }
      if times = @times[name]?
        packument["time"] = Json.new(times.transform_values { |t| Json.new(t) })
      end
      packument.to_json
    end

    private def build_tarball(package_json : Hash(String, Json), files : Hash(String, String)) : Bytes
      io = IO::Memory.new
      Compress::Gzip::Writer.open(io) do |gzip|
        tar = Crystar::Writer.new(gzip)
        write_entry(tar, "package/package.json", package_json.to_json, 0o644)
        files.each do |path, content|
          write_entry(tar, "package/#{path}", content, 0o644)
        end
        tar.close
      end
      io.to_slice
    end

    private def write_entry(tar : Crystar::Writer, name : String, content : String, mode : Int32) : Nil
      header = Crystar::Header.new(name: name, mode: mode.to_i64, size: content.bytesize.to_i64, flag: Crystar::REG.ord.to_u8)
      tar.write_header(header)
      tar.write(content.to_slice)
    end
  end

  # Creates a local git repository with the given package.json and files.
  def self.make_git_repo(repo : Path, package_json : String, files : Hash(String, String)) : Nil
    Dir.mkdir_p(repo)
    File.write(repo / "package.json", package_json)
    files.each { |path, content| File.write(repo / path, content) }
    Process.run("git", ["init", "-q", "-b", "main", repo.to_s])
    Process.run("git", ["-C", repo.to_s, "add", "."])
    env = {"GIT_AUTHOR_NAME" => "zap-tests", "GIT_AUTHOR_EMAIL" => "zap-tests@example.com", "GIT_COMMITTER_NAME" => "zap-tests", "GIT_COMMITTER_EMAIL" => "zap-tests@example.com"}
    Process.run("git", ["-C", repo.to_s, "commit", "-q", "-m", "init"], env: env)
  end

  # Runs a block with a fresh fixture registry, stopping it afterwards.
  # NOTE: the registry must be created inside the running example; servers
  # created at load time (describe level) stop accepting connections once
  # the spec framework starts executing examples.
  def self.with_registry(&)
    registry = Registry.new
    yield registry
  ensure
    registry.try(&.stop)
  end

  # Runs a real install in a fresh temporary project and yields the project
  # directory. The project's .npmrc points at the fixture registry.
  def self.install_project(registry : Registry, package_json : String, *, install_config : Commands::Install::Config = Commands::Install::Config.new, &) : Nil
    tmpdir = Path.new(Dir.tempdir, "zap-it-#{Random::Secure.hex(4)}")
    begin
      Dir.mkdir_p(tmpdir)
      File.write(tmpdir / "package.json", package_json)
      File.write(tmpdir / ".npmrc", "registry=#{registry.base_url}/\n")

      config = Core::Config.new.copy_with(
        prefix: tmpdir.to_s,
        store_path: (tmpdir / "store").to_s,
        silent: true,
      )
      ic = install_config.copy_with(workers: 1, frozen_lockfile: false, save: false)
      Commands::Install.run(config, ic, raise_on_failure: true, reporter: Reporter::Null.new)
      yield tmpdir
    ensure
      FileUtils.rm_rf(tmpdir)
    end
  end
end
