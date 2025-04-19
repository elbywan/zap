require "log"
require "./alias"
require "./file"
require "./git"
require "./registry"
require "./tarball_url"
require "./workspace"

module Commands::Install::Protocol
  Log = ::Log.for("zap.install.protocol")

  PROTOCOLS = {
    Protocol::Workspace,
    Protocol::Alias,
    Protocol::File,
    Protocol::Git,
    Protocol::TarballUrl,
    Protocol::Registry,
  }
end
