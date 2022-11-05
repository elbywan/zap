module Zap::Resolver
  class File < Base
    def resolve(parent_pkg : Lockfile | Package, *, dependent : Package?, validate_lockfile = false) : Package?
      path = Path.new version.to_s.split("file:").last
      Package.init(path).tap { |pkg|
        on_resolve(pkg, parent_pkg, :file, version.to_s, dependent)
        pkg.dist = {link: path.to_s}
        Zap.lockfile.pkgs[pkg.key] = pkg
      }
    end

    def store(metadata : Package, &on_downloading) : Bool
      false
    end
  end
end
