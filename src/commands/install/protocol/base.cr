require "./resolver"

module Zap::Commands::Install::Protocol
  record Aliased, name : String, alias : String do
    def to_s(io)
      io << "#{name} (alias:#{@alias})"
    end
  end

  record PathInfo, base_directory : String, path : Path do
    def self.from_str(str : String, base_directory : String) : PathInfo?
      unless str.starts_with?(".") || str.starts_with?("/") || str.starts_with?("~")
        return nil
      end

      path = Path.new(str).expand
      Protocol::PathInfo.new(base_directory: base_directory, path: path)
    end

    getter exists : Bool do
      @exists || ::File.exist?(@path)
    end

    getter? file : Bool do
      ::File.file?(@path)
    end

    getter? dir : Bool do
      ::File.directory?(@path)
    end

    def relative_path
      @path.relative_to(@base_directory)
    end
  end

  abstract struct Base
    macro inherited
      extend ClassMethods
    end

    private module ClassMethods
      abstract def normalize?(str : String, path_info : PathInfo?) : {String?, String?}?
      abstract def resolver?(state : Commands::Install::State,
                             name : String?,
                             specifier,
                             parent = nil,
                             dependency_type = nil,
                             skip_cache = false) : Protocol::Resolver?
    end
  end
end
