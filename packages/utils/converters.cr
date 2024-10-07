require "yaml"
require "msgpack"
require "concurrency/data_structures/safe_hash"

class Utils::Converters::OrderedSet(T)
  def self.to_yaml(value : Set(T)?, yaml : YAML::Nodes::Builder) : Nil
    if value.nil? || value.empty?
      nil.to_yaml(yaml)
    else
      value.to_a.sort!.to_yaml(yaml)
    end
  end

  def self.from_yaml(ctx : YAML::ParseContext, node : YAML::Nodes::Node) : Set(T)?
    if node.kind == "scalar"
      Nil.new(ctx, node)
    else
      Set(T).new(ctx, node)
    end
  end

  def self.to_msgpack(value, packer : MessagePack::Packer)
    if value.nil? || value.empty?
      nil.to_msgpack(packer)
    else
      value.to_a.sort!.to_msgpack(packer)
    end
  end

  def self.from_msgpack(pull : MessagePack::Unpacker)
    if pull.current_token.is_a?(Token::NullT)
      Nil.from_msgpack(pull)
    else
      Set(T).new.from_msgpack(pull)
    end
  end
end

class Utils::Converters::OrderedHash(T, U)
  def self.to_yaml(value : Hash(T, U)?, yaml : YAML::Nodes::Builder) : Nil
    if value.nil? || value.empty?
      nil.to_yaml(yaml)
    else
      value.to_a.sort_by!(&.[0]).to_h.to_yaml(yaml)
    end
  end

  def self.from_yaml(ctx : YAML::ParseContext, node : YAML::Nodes::Node) : Hash(T, U)?
    if node.kind == "scalar"
      Nil.new(ctx, node)
    else
      Hash(T, U).new(ctx, node)
    end
  end

  def self.to_msgpack(value, packer : MessagePack::Packer)
    if value.nil? || value.empty?
      nil.to_msgpack(packer)
    else
      value.to_a.sort_by!(&.[0]).to_h.to_msgpack(packer)
    end
  end

  def self.from_msgpack(pull : MessagePack::Unpacker)
    if pull.current_token.is_a?(MessagePack::Token::NullT)
      Nil.new(pull)
    else
      Hash(T, U).new(pull)
    end
  end
end

class Utils::Converters::OrderedSafeHash(T, U)
  def self.to_yaml(value : Concurrency::SafeHash(T, U)?, yaml : YAML::Nodes::Builder) : Nil
    if value.nil? || value.empty?
      nil.to_yaml(yaml)
    else
      value.to_a.sort_by!(&.[0]).to_h.to_yaml(yaml)
    end
  end

  def self.from_yaml(ctx : YAML::ParseContext, node : YAML::Nodes::Node) : Concurrency::SafeHash(T, U)?
    if node.kind == "scalar"
      Nil.new(ctx, node)
    else
      Concurrency::SafeHash(T, U).new(ctx, node)
    end
  end

  def self.to_msgpack(value, packer : MessagePack::Packer)
    if value.nil? || value.empty?
      nil.to_msgpack(packer)
    else
      value.to_a.sort_by!(&.[0]).to_h.to_msgpack(packer)
    end
  end

  def self.from_msgpack(pull : MessagePack::Unpacker)
    if pull.current_token.is_a?(MessagePack::Token::NullT)
      Nil.new(pull)
    else
      Concurrency::SafeHash(T, U).new(pull)
    end
  end
end
