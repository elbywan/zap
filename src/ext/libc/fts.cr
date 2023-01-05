{% if flag?(:unix) %}
  lib LibC
    #########################################################
    # FTS Bindings                                          #
    #########################################################
    # See: https://man7.org/linux/man-pages/man3/fts.3.html #
    #########################################################

    # fun fts_open(path_argv : LibC::Char**, options : LibC::FTSOpenOptions, compar : (LibC::FTSEnt*, LibC::FTSEnt*) -> LibC::Int) : LibC::FTS*
    fun fts_open(path_argv : LibC::Char**, options : LibC::FTSOpenOptions, compar : LibC::Int) : LibC::FTS*
    fun fts_read(ftsp : LibC::FTS*) : LibC::FTSEnt*
    fun fts_children(ftsp : LibC::FTS*, instr : LibC::FTSChildrenOptions) : LibC::FTSEnt*
    fun fts_set(ftsp : LibC::FTS*, f : LibC::FTSEnt*, instr : LibC::FTSSetOptions) : LibC::Int
    fun fts_close(ftsp : LibC::FTS*) : LibC::Int

    # One of the following values describing the returned FTSENT
    # structure and the file it represents.  With the exception
    # of directories without errors (FTS_D), all of these
    # entries are terminal, that is, they will not be revisited,
    # nor will any of their descendants be visited.
    enum FTSInfo : LibC::UShort
      # preorder directory
      FTS_D = 1
      # directory that causes cycles
      FTS_DC
      # none of the above
      FTS_DEFAULT
      # unreadable directory
      FTS_DNR
      # dot or dot-dot
      FTS_DOT
      # postorder directory
      FTS_DP
      # error; errno is set
      FTS_ERR
      # regular file
      FTS_F
      # initialized only
      FTS_INIT
      # stat(2) failed
      FTS_NS
      # no stat(2) requested
      FTS_NSOK
      # symbolic link
      FTS_SL
      # symbolic link without target
      FTS_SLNONE
    end

    @[Flags]
    enum FTSOpenOptions : LibC::Int
      # Follow command line symlinks.
      FTS_COMFOLLOW
      # Logical walk.
      FTS_LOGICAL
      # Don't change directories.
      FTS_NOCHDIR
      # Don't get stat info.
      FTS_NOSTAT
      # Physical walk.
      FTS_PHYSICAL
      # Return dot and dot-dot.
      FTS_SEEDOT
      # Don't cross devices.
      FTS_XDEV
      # Valid user option mask.
      FTS_OPTIONMASK
      # (private) child names only
      # FTS_NAMEONLY
      # (private) unrecoverable error
      # FTS_STOP
    end

    enum FTSChildrenOptions : LibC::Int
      NONE = 0
      # Only the names of the files are needed.
      FTS_NAMEONLY
    end

    enum FTSSetOptions : LibC::Int
      NONE = 0
      # re-visit this node
      FTS_AGAIN
      # follow symbolic link
      FTS_FOLLOW
      # skip this node
      FTS_SKIP
    end

    # Opaque handle for fts functions.
    type FTS = Void*

    struct FTSEnt
      # If a directory causes a cycle in the hierarchy (see FTS_DC), either because of a hard link between two directories,
      # or a symbolic link pointing to a directory, the fts_cycle field of the structure will point to the FTSENT structure in the hierarchy
      # that references the same file as the current FTSENT structure.  Otherwise, the contents of the fts_cycle field are undefined.
      fts_cycle : LibC::FTSEnt*
      #  A pointer to the FTSENT structure referencing the file in the hierarchy immediately above the current file, that is,
      # the directory of which this file is a member.
      # A parent structure for the initial entry point is provided as well,
      # however, only the fts_level, fts_number, and fts_pointer fields are guaranteed to be initialized.
      fts_parent : LibC::FTSEnt*
      # Upon return from the fts_children() function, the fts_link field points to the next structure in the NULL-terminated
      # linked list of directory members.  Otherwise, the contents of the fts_link field are undefined.
      fts_link : LibC::FTSEnt*
      # This field is provided for the use of the application program and is not modified by the fts functions.
      # It is initialized to 0.
      fts_number : LibC::Long
      # This field is provided for the use of the application program and is not modified by the fts functions.
      # It is initialized to NULL.
      fts_pointer : Void*
      # A path for accessing the file from the current directory.
      fts_accpath : LibC::Char*
      # The path for the file relative to the root of the traversal.
      # This path contains the path specified to fts_open() as a prefix.
      fts_path : LibC::Char*
      # If fts_children() or fts_read() returns an FTSENT structure whose fts_info field is set to FTS_DNR, FTS_ERR,
      # or FTS_NS, the fts_errno field contains the error number (i.e., the errno value) specifying the cause of the error.
      # Otherwise, the contents of the fts_errno field are undefined.
      fts_errno : LibC::Int
      # fd for symlink
      fts_symfd : LibC::Int
      # The sum of the lengths of the strings referenced by fts_path and fts_name.
      fts_pathlen : LibC::UShort
      # The length of the string referenced by fts_name.
      fts_namelen : LibC::UShort
      # inode
      fts_ino : Int32 # Weird but works on darwin? (proper type is supposed to be LibC::InoT)
      # device
      fts_dev : LibC::DevT
      # link count
      fts_nlink : LibC::NlinkT
      # The depth of the traversal, numbered from -1 to N, where this file was found.
      # The FTSENT structure representing the parent of the starting point (or root) of the traversal is numbered -1,
      # and the FTSENT structure for the root itself is numbered 0.
      fts_level : LibC::Short
      # See own definition.
      fts_info : LibC::FTSInfo
      # private flags for FTSENT structure
      fts_flags : LibC::UShort
      # fts_set() instructions
      fts_instr : LibC::UShort
      # A pointer to stat(2) information for the file.
      fts_statp : LibC::Stat*

      # padding
      __padding : LibC::UShort

      # The name of the file.
      fts_name : LibC::Char[0]
    end
  end
{% end %}
