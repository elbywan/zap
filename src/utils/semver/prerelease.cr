struct Zap::Utils::Semver::Prerelease
  include Comparable(self)

  getter name : String
  getter version : UInt128? = nil
  def_clone

  def initialize(prerelease_string : String)
    split_str = prerelease_string.split(".")
    if split_str.size > 1 && (version_number = split_str.last.to_u128?)
      @name = split_str[...-1].join('.')
      @version = version_number
    else
      @name = prerelease_string
    end
  end

  def <=>(other : self) : Int32
    return name <=> other.name if other.name != name
    (version || 0_u128) <=> (other.version || 0_u128)
  end

  def to_s(io)
    io << @name
    io << "." << @version if @version
  end

  def empty?
    name.empty? && version.nil?
  end
end
