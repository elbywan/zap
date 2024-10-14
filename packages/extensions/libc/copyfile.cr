{% if flag?(:darwin) %}
  lib LibC
    COPYFILE_ACL                 = 1 << 0
    COPYFILE_STAT                = (1 << 1)
    COPYFILE_XATTR               = (1 << 2)
    COPYFILE_DATA                = (1 << 3)
    COPYFILE_SECURITY            = (COPYFILE_STAT | COPYFILE_ACL)
    COPYFILE_METADATA            = (COPYFILE_SECURITY | COPYFILE_XATTR)
    COPYFILE_ALL                 = (COPYFILE_METADATA | COPYFILE_DATA)
    COPYFILE_RECURSIVE           = (1 << 15) # Descend into hierarchies
    COPYFILE_CHECK               = (1 << 16) # return flags for xattr or acls if set
    COPYFILE_EXCL                = (1 << 17) # fail if destination exists
    COPYFILE_NOFOLLOW_SRC        = (1 << 18) # don't follow if source is a symlink
    COPYFILE_NOFOLLOW_DST        = (1 << 19) # don't follow if dst is a symlink
    COPYFILE_MOVE                = (1 << 20) # unlink src after copy
    COPYFILE_UNLINK              = (1 << 21) # unlink dst before copy
    COPYFILE_NOFOLLOW            = (COPYFILE_NOFOLLOW_SRC | COPYFILE_NOFOLLOW_DST)
    COPYFILE_PACK                = (1 << 22)
    COPYFILE_UNPACK              = (1 << 23)
    COPYFILE_CLONE               = (1 << 24)
    COPYFILE_CLONE_FORCE         = (1 << 25)
    COPYFILE_RUN_IN_PLACE        = (1 << 26)
    COPYFILE_VERBOSE             = (1 << 30)
    COPYFILE_RECURSE_ERROR       = 0
    COPYFILE_RECURSE_FILE        = 1
    COPYFILE_RECURSE_DIR         = 2
    COPYFILE_RECURSE_DIR_CLEANUP = 3
    COPYFILE_COPY_DATA           = 4
    COPYFILE_COPY_XATTR          = 5
    COPYFILE_START               = 1
    COPYFILE_FINISH              = 2
    COPYFILE_ERR                 = 3
    COPYFILE_PROGRESS            = 4
    COPYFILE_CONTINUE            = 0
    COPYFILE_SKIP                = 1
    COPYFILE_QUIT                = 2

    fun copyfile(from : LibC::Char*, to : LibC::Char*, copyfile_state_t : Void*, flags : LibC::Int) : LibC::Int
    fun fcopyfile(from : LibC::Int, to : LibC::Int, copyfile_state_t : Void*, flags : LibC::Int) : LibC::Int
  end
{% end %}
