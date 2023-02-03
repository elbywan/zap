module Zap::Utils::Various
  def self.parse_key(raw_key : String)
    split_key = raw_key.split('@')
    if raw_key.starts_with?("@")
      name = split_key[0..1].join('@')
      version = split_key[2]?
    else
      name = split_key.first
      version = split_key[1]?
    end
    return name, version
  end
end
