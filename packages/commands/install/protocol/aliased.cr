module Commands::Install::Protocol
  record Aliased, name : String, alias : String do
    def to_s(io)
      io << "#{name} (alias:#{@alias})"
    end
  end
end
