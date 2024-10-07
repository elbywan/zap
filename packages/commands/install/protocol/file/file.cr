require "../../resolver"
require "../base"
require "./resolver"

struct Commands::Install::Protocol::File < Commands::Install::Protocol::Base
  def self.normalize?(str : String, path_info : PathInfo?) : {String?, String?}?
    return nil unless path_info
    path_str = path_info.path.to_s

    if path_info.dir?
      # npm install <folder>
      return "file:#{path_info.relative_path}", nil
    elsif path_info.file? && (path_str.ends_with?(".tgz") || path_str.ends_with?(".tar.gz") || path_str.ends_with?(".tar"))
      # npm install <tarball file>
      return "file:#{path_info.relative_path}", nil
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
