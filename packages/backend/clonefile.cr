require "extensions/libc/clonefile"

module Backend::CloneFile
  def self.install(src_path : String | Path, dest_path : String | Path) : Bool
    result = LibC.clonefile(src_path.to_s, dest_path.to_s, 0)
    if result == -1
      raise "Error cloning file: #{Errno.value} #{src_path.to_s} -> #{dest_path.to_s}"
    end
    true
  end
end
