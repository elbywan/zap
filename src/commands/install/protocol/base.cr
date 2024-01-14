require "./resolver"

module Zap::Commands::Install::Protocol
  record Aliased, name : String, alias : String do
    def to_s(io)
      io << "#{name} (alias:#{@alias})"
    end
  end

  abstract struct Base
    macro inherited
      extend ClassMethods
    end

    private module ClassMethods
      abstract def normalize?(str : String, base_directory : String, path : Path?) : {String?, String?}?
      abstract def resolver?(state : Commands::Install::State,
                             name : String?,
                             specifier,
                             parent = nil,
                             dependency_type = nil,
                             skip_cache = false) : Protocol::Resolver?
    end
  end
end
