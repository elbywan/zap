require "../base"
require "./resolver"

struct Zap::Commands::Install::Protocol::File < Zap::Commands::Install::Protocol::Base
  def self.normalize?(str : String, base_directory : String, path : Path?) : {String?, String?}?
    return nil unless path
    path_str = path.to_s
    if ::File.directory?(path)
      # npm install <folder>
      return "file:#{path.relative_to(base_directory)}", nil
    elsif ::File.file?(path) && (path_str.ends_with?(".tgz") || path_str.ends_with?(".tar.gz") || path_str.ends_with?(".tar"))
      # npm install <tarball file>
      return "file:#{path.relative_to(base_directory)}", nil
    end
  end

  def self.resolver?(
    state : Commands::Install::State,
    name : String?,
    specifier,
    parent = nil,
    dependency_type = nil,
    skip_cache = false
  ) : Protocol::Resolver?
    if specifier.starts_with? "file:"
      Log.debug { "(#{name}@#{specifier}) Resolved as a file dependency" }
      Resolver.new(state, name, specifier, parent, dependency_type, skip_cache)
    end
  end
end
