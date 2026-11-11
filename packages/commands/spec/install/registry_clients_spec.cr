require "spec"
require "file_utils"
require "data/npmrc"
require "../../install/registry_clients"

describe Commands::Install::RegistryClients do
  it "matches registry origins and path boundaries exactly" do
    dir = Path.new(Dir.tempdir, "zap-registry-clients-#{Random::Secure.hex(4)}")
    begin
      Dir.mkdir_p(dir)
      clients = Commands::Install::RegistryClients.new(
        dir.to_s,
        Data::Npmrc.new(dir),
        network_protocol: "http1"
      )
      base = "http://registry.example/npm"
      pool = clients.get_or_init_pool(base)

      key, found = clients.find_or_init_pool("http://registry.example/npm/pkg/-/pkg-1.0.0.tgz")
      key.should eq(base)
      found.base_url.should eq(pool.base_url)

      _, sibling = clients.find_or_init_pool("http://registry.example/npm2/pkg.tgz")
      sibling.base_url.should_not eq(pool.base_url)

      _, other_host = clients.find_or_init_pool("http://registry.example.evil/npm/pkg.tgz")
      other_host.base_url.should_not eq(pool.base_url)
    ensure
      Commands::Install::RegistryClients.close
      FileUtils.rm_rf(dir)
    end
  end
end
