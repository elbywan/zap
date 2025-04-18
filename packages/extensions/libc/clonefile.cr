{% if flag?(:darwin) %}
  lib LibC
    {% if flag?(:x86_64) %}
    AT_FDCWD          =     -2 # Descriptor value for the current working directory
    {% end %}
    CLONE_NOFOLLOW    = 0x0001 # Don't follow symbolic links
    CLONE_NOOWNERCOPY = 0x0002 # Don't copy ownership information from source
    fun clonefile(const : LibC::Char*, to : LibC::Char*, flags : LibC::Int) : LibC::Int
    fun clonefileat(src_dirfd : LibC::Int, src : LibC::Char*, dst_dirfd : LibC::Int, dst : LibC::Char*, flags : LibC::Int) : LibC::Int
    fun fclonefileat(srcfd : LibC::Int, dst_dirfd : LibC::Int, dst : LibC::Char*, flags : LibC::Int) : LibC::Int
  end
{% end %}
