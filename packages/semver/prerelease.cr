struct Semver::Prerelease
  include Comparable(self)

  # Getter for the name of the prerelease
  getter name : String
  # Getter for the version of the prerelease, which is optional (can be nil)
  getter version : UInt128? = nil
  def_clone

  # Initializes a new Prerelease instance from a prerelease string
  def initialize(prerelease_string : String)
    split_str = prerelease_string.split(".")
    # If the last part of the split string can be converted to a UInt128, it is considered the version
    if split_str.size > 1 && (version_number = split_str.last.to_u128?)
      @name = split_str[...-1].join('.')
      @version = version_number
    else
      @name = prerelease_string
    end
  end

  # Compares this Prerelease instance with another for sorting
  def <=>(other : self) : Int32
    # Compare by name first
    return name <=> other.name if other.name != name
    # If names are equal, compare by version (treat nil as 0)
    (version || 0_u128) <=> (other.version || 0_u128)
  end

  # Converts the Prerelease instance to a string representation
  def to_s(io)
    io << @name
    io << "." << @version if @version
  end

  # Checks if the Prerelease instance is empty (no name and no version)
  def empty?
    name.empty? && version.nil?
  end
end
