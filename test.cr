require "./src/ext/**"

def recursively(src_path : Path | String, dest_path : Path | String, &block : (String | Path, String | Path) -> Nil)
  if Dir.exists?(src_path)
    Dir.mkdir(dest_path) unless Dir.exists?(dest_path)
    Dir.each_child(src_path) do |entry|
      src = File.join(src_path, entry)
      dest = File.join(dest_path, entry)
      recursively(src, dest, &block)
    end
  else
    yield(src_path, dest_path)
  end
end

# recursively("./node_modules", "./node_modules2") do |src, dest|
#   spawn do
#     fd_src = File.open(src, mode: "r")
#     fd_dest = File.open(dest, mode: "w")
#     # LibC.copyfile(src.to_s, dest.to_s, nil, LibC::COPYFILE_ALL | LibC::COPYFILE_CLONE)
#     # File.link(src, dest)
#     # LibC.clonefile(src.to_s, dest.to_s, 0)
#     LibC.fcopyfile(fd_src.fd, fd_dest.fd, nil, LibC::COPYFILE_ALL | LibC::COPYFILE_CLONE)
#   ensure
#     fd_src.try &.close
#     fd_dest.try &.close
#   end
# end
# puts "before yield"
# Fiber.yield
# puts "after yield"
# or:
# spawn do
#   puts "spawn 1"
#   fd_src = File.open("./log.txt", mode: "r")
#   fd_dest = File.open("./log2.txt", mode: "w")
#   fd_src.blocking = false
#   fd_dest.blocking = false
#   puts LibC.fcopyfile(fd_src.fd, fd_dest.fd, nil, LibC::COPYFILE_ALL | LibC::COPYFILE_CLONE)
#   # puts File.link("./log.txt", "./log2.txt")
#   puts "spawn 2"
# end
# puts "before yield"
# Fiber.yield
# puts "after yield"

LibC.clonefile("./node_modules", "./node_modules2", 0)

# output = STDOUT
# output.puts "\nhello"
# output.flush
# output << "hello"
# output.flush
# sleep 1
# output << "world"
# output.flush
