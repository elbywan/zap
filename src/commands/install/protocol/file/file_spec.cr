require "../spec_helper"
require "./file"

struct Zap::Commands::Install::Protocol::PathInfo
  setter file : Bool?
  setter dir : Bool?
end

module Zap::Commands::Install::Protocol::File::Spec
  describe File, tags: "protocol" do
    base_directory = Dir.current

    {
      { {specifier: "#{base_directory}/../non-existing", file: false, dir: false}, nil },
      { {specifier: "#{base_directory}/../package", file: false, dir: true}, {"file:../package", nil} },
      { {specifier: "../package", file: false, dir: true}, {"file:../package", nil} },
      { {specifier: "./dir/package.tgz", file: true, dir: false}, {"file:dir/package.tgz", nil} },
      { {specifier: "./dir/package.tar", file: true, dir: false}, {"file:dir/package.tar", nil} },
      { {specifier: "./dir/package.tar.gz", file: true, dir: false}, {"file:dir/package.tar.gz", nil} },
      { {specifier: "./dir/package.tar.gz", file: false, dir: false}, nil },
    }.each do |(specifier_data, expected)|
      it "should normalize specifiers (#{specifier_data[:specifier]})" do
        specifier = specifier_data[:specifier]
        path_info = PathInfo.from_str(specifier, base_directory)
        if path_info
          path_info.file = specifier_data[:file]
          path_info.dir = specifier_data[:dir]
        end

        Protocol::File.normalize?(specifier, path_info).should eq(expected)
      end
    end

    {
      "file:../package",
      "file:dir/package.tgz",
      "file:dir/package.tar",
    }.each do |specifier|
      name = "package_name"
      it "should instantiate a fresh resolver" do
        resolver = File.resolver?(
          state: SpecHelper::DUMMY_STATE,
          name: name,
          specifier: specifier,
        )
        resolver.should_not be_nil
        raise "resolver should not be nil" if resolver.nil?
        resolver.is_a?(File::Resolver).should be_true
        resolver.name.should eq(name)
        resolver.specifier.should eq(specifier)
      end
    end
  end
end
