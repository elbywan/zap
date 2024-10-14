require "../base"
require "../resolver"
require "utils/targzip"

struct Commands::Install::Protocol::TarballUrl < Commands::Install::Protocol::Base
end

struct Commands::Install::Protocol::TarballUrl::Resolver < Commands::Install::Protocol::Resolver
  def resolve(*, pinned_version : String? = nil) : Data::Package
    tarball_url = specifier.to_s
    @state.store.with_lock(tarball_url, @state.config) do
      temp_path = @state.store.store_temp_tarball(tarball_url)
      Data::Package.init(temp_path).tap { |pkg|
        pkg.dist = Data::Package::Dist::Tarball.new(tarball_url, temp_path.to_s)
        on_resolve(pkg)
      }
    end
  end

  def valid?(metadata : Data::Package) : Bool
    false
  end

  def store?(metadata : Data::Package, &on_downloading) : Bool
    dist = metadata.dist.as(Data::Package::Dist::Tarball)
    return false if Dir.exists?(dist.path)
    yield
    state.store.with_lock(dist.tarball, state.config) do
      Utils::TarGzip.download_and_unpack(dist.tarball, Path.new(dist.path))
    end
    true
  end
end
