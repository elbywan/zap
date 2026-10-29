require "extensions/libc/clonefile"

module Backend::CloneFile
  # clonefile requires an absent destination. A nested dependency can create
  # the package directory (`<pkg>/node_modules`) while the parent link is
  # still in flight, so surface that case to the caller for a merging copy.
  class DestinationExists < Exception
    def initialize(src_path : String, dest_path : String)
      super("Destination already exists: #{dest_path} (source: #{src_path})")
    end
  end

  def self.link(src_path : String | Path, dest_path : String | Path) : Bool
    result = LibC.clonefile(src_path.to_s, dest_path.to_s, 0)
    if result == -1
      errno = Errno.value
      raise DestinationExists.new(src_path.to_s, dest_path.to_s) if errno == Errno::EEXIST
      raise "Error cloning file: #{errno} #{src_path.to_s} -> #{dest_path.to_s}"
    end
    true
  end
end
