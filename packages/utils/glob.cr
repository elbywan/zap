###
# Cloned from the crystal standard library.
#
# Enhanced with the ability to exclude files and directories.
###
module Utils::Glob
  # Returns an array of all files that match against any of *patterns*.
  #
  # The pattern syntax is similar to shell filename globbing, see `File.match?` for details.
  #
  # NOTE: Path separator in patterns needs to be always `/`. The returned file names use system-specific path separators.
  def self.[](*patterns : Path | String, match_hidden = false, follow_symlinks = false, exclude : Array(String)? = nil) : Array(String)
    glob(patterns, match_hidden: match_hidden, follow_symlinks: follow_symlinks, exclude: exclude)
  end

  # :ditto:
  def self.[](patterns : Enumerable, match_hidden = false, follow_symlinks = false, exclude : Array(String)? = nil) : Array(String)
    glob(patterns, match_hidden: match_hidden, follow_symlinks: follow_symlinks, exclude: exclude)
  end

  # Returns an array of all files that match against any of *patterns*.
  #
  # The pattern syntax is similar to shell filename globbing, see `File.match?` for details.
  #
  # If *match_hidden* is `true` the pattern will match hidden files and folders.
  #
  # NOTE: Path separator in patterns needs to be always `/`. The returned file names use system-specific path separators.
  def self.glob(*patterns : Path | String, match_hidden = false, follow_symlinks = false, exclude : Array(String)? = nil) : Array(String)
    glob(patterns, match_hidden: match_hidden, follow_symlinks: follow_symlinks, exclude: exclude)
  end

  # :ditto:
  def self.glob(patterns : Enumerable, match_hidden = false, follow_symlinks = false, exclude : Array(String)? = nil) : Array(String)
    paths = [] of String
    glob(patterns, match_hidden: match_hidden, follow_symlinks: follow_symlinks, exclude: exclude) do |path|
      paths << path
    end
    paths
  end

  # Yields all files that match against any of *patterns*.
  #
  # The pattern syntax is similar to shell filename globbing, see `File.match?` for details.
  #
  # If *match_hidden* is `true` the pattern will match hidden files and folders.
  #
  # NOTE: Path separator in patterns needs to be always `/`. The returned file names use system-specific path separators.
  def self.glob(*patterns : Path | String, match_hidden = false, follow_symlinks = false, exclude : Array(String)? = nil, &block : String -> _)
    glob(patterns, match_hidden: match_hidden, follow_symlinks: follow_symlinks, exclude: exclude) do |path|
      yield path
    end
  end

  # :ditto:
  def self.glob(patterns : Enumerable, match_hidden = false, follow_symlinks = false, exclude : Array(String)? = nil, &block : String -> _)
    Globber.glob(patterns, match_hidden: match_hidden, follow_symlinks: follow_symlinks, exclude: exclude) do |path|
      yield path
    end
  end

  # :nodoc:
  module Globber
    record DirectoriesOnly
    record ConstantEntry, path : String, merged : Bool
    record EntryMatch, pattern : String do
      def matches?(string) : Bool
        ::File.match?(pattern, string)
      end
    end
    record RecursiveDirectories
    record ConstantDirectory, path : String
    record RootDirectory
    record DirectoryMatch, pattern : String do
      def matches?(string) : Bool
        ::File.match?(pattern, string)
      end
    end
    alias PatternType = DirectoriesOnly | ConstantEntry | EntryMatch | RecursiveDirectories | ConstantDirectory | RootDirectory | DirectoryMatch

    def self.glob(patterns : Enumerable, *, match_hidden, follow_symlinks, exclude, &block : String -> _)
      patterns.each do |pattern|
        if pattern.is_a?(Path)
          pattern = pattern.to_posix.to_s
        end
        sequences = compile(pattern)

        sequences.each do |sequence|
          if sequence.count(&.is_a?(RecursiveDirectories)) > 1
            run_tracking(sequence, match_hidden: match_hidden, follow_symlinks: follow_symlinks, exclude: exclude) do |match|
              yield match
            end
          else
            run(sequence, match_hidden: match_hidden, follow_symlinks: follow_symlinks, exclude: exclude) do |match|
              yield match
            end
          end
        end
      end
    end

    private def self.compile(pattern)
      expanded_patterns = [] of String
      ::Dir::Globber.expand_brace_pattern(pattern, expanded_patterns)

      expanded_patterns.map do |expanded_pattern|
        single_compile expanded_pattern
      end
    end

    private def self.single_compile(glob)
      list = [] of PatternType
      return list if glob.empty?

      parts = glob.split('/', remove_empty: true)

      if glob.ends_with?('/')
        list << DirectoriesOnly.new
      else
        file = parts.pop
        if constant_entry?(file)
          list << ConstantEntry.new file, false
        elsif !file.empty?
          list << EntryMatch.new file
        end
      end

      parts.reverse_each do |dir|
        case
        when dir == "**"
          list << RecursiveDirectories.new
        when dir.empty?
        when constant_entry?(dir)
          case last = list[-1]
          when ConstantDirectory
            list[-1] = ConstantDirectory.new ::File.join(dir, last.path)
          when ConstantEntry
            list[-1] = ConstantEntry.new ::File.join(dir, last.path), true
          else
            list << ConstantDirectory.new dir
          end
        else
          list << DirectoryMatch.new dir
        end
      end

      if glob.starts_with?('/')
        list << RootDirectory.new
      end

      list
    end

    private def self.constant_entry?(file)
      file.each_char do |char|
        return false if char == '*' || char == '?'
      end

      true
    end

    private def self.run_tracking(sequence, match_hidden, follow_symlinks, exclude, &block : String -> _)
      result_tracker = Set(String).new

      run(sequence, match_hidden, follow_symlinks, exclude) do |result|
        if result_tracker.add?(result)
          yield result
        end
      end
    end

    private def self.run(sequence, match_hidden, follow_symlinks, exclude, &block : String -> _)
      return if sequence.empty?

      path_stack = [] of {Int32, String?, Crystal::System::Dir::Entry?}
      path_stack << {sequence.size - 1, nil, nil}

      while !path_stack.empty?
        pos, path, dir_entry = path_stack.pop
        cmd = sequence[pos]

        next if exclude.try &.any? { |ex| ex == Path.new(path).basename } if path

        next_pos = pos - 1
        case cmd
        in RootDirectory
          raise "unreachable" if path
          path_stack << {next_pos, root, nil}
        in DirectoriesOnly
          raise "unreachable" unless path
          # FIXME: [win32] File::SEPARATOR_STRING comparison is not sufficient for Windows paths.
          if path == ::File::SEPARATOR_STRING
            fullpath = path
          else
            fullpath = Path[path].join("").to_s
          end

          if dir_entry && !dir_entry.dir?.nil?
            yield fullpath
          elsif dir?(fullpath, follow_symlinks)
            yield fullpath
          end
        in EntryMatch
          next if sequence[pos + 1]?.is_a?(RecursiveDirectories)
          each_child(path) do |entry|
            next if exclude.try &.any? { |ex| ex == entry.name }
            next if !match_hidden && entry.name.starts_with?('.')
            yield join(path, entry.name) if cmd.matches?(entry.name)
          end
        in DirectoryMatch
          next_cmd = sequence[next_pos]?

          each_child(path) do |entry|
            if cmd.matches?(entry.name)
              is_dir = entry.dir?
              fullpath = join(path, entry.name)
              if is_dir.nil?
                is_dir = dir?(fullpath, follow_symlinks)
              end
              if is_dir
                path_stack << {next_pos, fullpath, entry}
              end
            end
          end
        in ConstantEntry
          unless cmd.merged
            next if sequence[pos + 1]?.is_a?(RecursiveDirectories)
          end
          full = join(path, cmd.path)
          yield full if ::File.exists?(full) || ::File.symlink?(full)
        in ConstantDirectory
          path_stack << {next_pos, join(path, cmd.path), nil}
          # Don't check if full exists. It just costs us time
          # and the downstream node will be able to check properly.
        in RecursiveDirectories
          path_stack << {next_pos, path, nil}
          next_cmd = sequence[next_pos]?

          dir_path = path || ""
          dir_stack = [] of Dir
          dir_path_stack = [dir_path]
          begin
            dir = Dir.new(path || ".")
            dir_stack << dir
          rescue ::File::Error
            next
          end
          recurse = false

          until dir_path_stack.empty?
            if recurse
              begin
                dir = Dir.new(dir_path)
              rescue ::File::Error
                dir_path_stack.pop
                break if dir_path_stack.empty?
                dir_path = dir_path_stack.last
                next
              ensure
                recurse = false
              end
              dir_stack.push dir
            end

            if entry = read_entry(dir)
              next if entry.name.in?(".", "..")
              next if !match_hidden && entry.name.starts_with?('.')
              next if exclude.try &.any? { |ex| ex == entry.name }

              if dir_path.bytesize == 0
                fullpath = entry.name
              else
                fullpath = File.join(dir_path, entry.name)
              end

              case next_cmd
              when ConstantEntry
                unless next_cmd.merged
                  yield fullpath if next_cmd.path == entry.name
                end
              when EntryMatch
                yield fullpath if next_cmd.matches?(entry.name)
              end

              is_dir = entry.dir?
              if is_dir.nil?
                is_dir = dir?(fullpath, follow_symlinks)
              end

              if is_dir
                path_stack << {next_pos, fullpath, entry}

                dir_path_stack.push fullpath
                dir_path = dir_path_stack.last
                recurse = true
                next
              end
            else
              dir.try(&.close)
              dir_path_stack.pop
              dir_stack.pop
              break if dir_path_stack.empty?
              dir_path = dir_path_stack.last
              dir = dir_stack.last
            end
          end
        end
      end
    end

    private def self.root
      # TODO: better implementation for windows?
      {% if flag?(:windows) %}
        "C:\\"
      {% else %}
        ::File::SEPARATOR_STRING
      {% end %}
    end

    private def self.dir?(path, follow_symlinks)
      if info = ::File.info?(path, follow_symlinks: follow_symlinks)
        info.type.directory?
      else
        false
      end
    end

    private def self.join(path, entry)
      return entry unless path
      return "#{root}#{entry}" if path == ::File::SEPARATOR_STRING

      ::File.join(path, entry)
    end

    private def self.each_child(path, &)
      Dir.open(path || Dir.current) do |dir|
        while entry = read_entry(dir)
          next if entry.name == "." || entry.name == ".."
          yield entry
        end
      end
    rescue exc : ::File::NotFoundError
    end

    private def self.read_entry(dir)
      return unless dir

      # By doing this we get an Entry struct which already tells us
      # whether something is a directory or not, avoiding having to
      # call File.info? which is really expensive.
      Crystal::System::Dir.next_entry(dir.@dir, dir.path)
    end
  end
end
