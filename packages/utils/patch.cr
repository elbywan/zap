require "log"
require "./directories"

# Unified-diff parsing, application and generation (git-style patches),
# used by the `zap patch` feature. In-house: no external patch tool, so it
# works on every platform with no process spawns.
module Utils::Patch
  Log = ::Log.for("zap.utils.patch")

  enum Status
    Modified
    Created
    Deleted
  end

  record Hunk, old_start : Int32, old_count : Int32, new_start : Int32, new_count : Int32, lines : Array(String)

  # A patch section for one file. The path is only known once the `+++`
  # line is seen, so the fields are mutable.
  class FileSection
    property path : String = ""
    property status : Status = Status::Modified
    property newline : Bool = true
    property hunks : Array(Hunk) = [] of Hunk
  end

  # Applies a git-style unified diff to the files under *root*. Raises when
  # the patch does not parse or a hunk does not match (strict, like pnpm).
  def self.apply(patch_text : String, root : Path) : Nil
    parse(patch_text).each do |file|
      raise "Cannot apply patch: absolute path: #{file.path}" if file.path.starts_with?('/')
      target = root / file.path
      case file.status
      when .deleted?
        ::File.delete?(target)
      when .created?
        Utils::Directories.mkdir_p(target.dirname)
        write_lines(target, apply_hunks(file.hunks, [] of String, file.path), file.newline)
      when .modified?
        unless ::File.exists?(target)
          raise "Cannot apply patch: file not found: #{file.path}"
        end
        original = ::File.read(target).chomp('\n').split('\n', remove_empty: false)
        write_lines(target, apply_hunks(file.hunks, original, file.path), file.newline)
      end
    end
  end

  # Generates a git-style unified diff between two directory trees. Files
  # equal in both are skipped; the patch paths are relative to the trees.
  # *exclude* (a relative path) is skipped, for helper files like the
  # `.zap-patch.json` marker.
  def self.generate(original_dir : Path, modified_dir : Path, exclude : String? = nil) : String
    sections = [] of String
    files = [] of String
    walk(modified_dir, files)
    files.sort!.each do |rel|
      next if rel == exclude
      original = original_dir / rel
      if ::File.exists?(original)
        original_text = ::File.read(original)
        modified_text = ::File.read(modified_dir / rel)
        sections << section(rel, Status::Modified, original_text, modified_text) if original_text != modified_text
      else
        sections << section(rel, Status::Created, "", ::File.read(modified_dir / rel))
      end
    end
    originals = [] of String
    walk(original_dir, originals)
    originals.sort!.each do |rel|
      next if rel == exclude
      next if ::File.exists?(modified_dir / rel)
      sections << section(rel, Status::Deleted, ::File.read(original_dir / rel), "")
    end
    sections.join
  end

  # -- private --

  private def self.section(rel : String, status : Status, original : String, modified : String) : String
    diff = file_diff(original, modified)
    case status
    when .created?
      "--- /dev/null\n+++ b/#{rel}\n" + diff
    when .deleted?
      "--- a/#{rel}\n+++ /dev/null\n" + diff
    else
      "--- a/#{rel}\n+++ b/#{rel}\n" + diff
    end
  end

  private def self.file_diff(original : String, modified : String) : String
    original_lines = original.chomp('\n').split('\n', remove_empty: false)
    modified_lines = modified.chomp('\n').split('\n', remove_empty: false)
    diff = line_diff(original_lines, modified_lines)
    return "" if diff.empty?
    body = String.build do |str|
      group_hunks(diff).each do |hunk|
        str << "@@ -#{hunk[:old_start]},#{hunk[:old_count]} +#{hunk[:new_start]},#{hunk[:new_count]} @@\n"
        hunk[:lines].each { |line| str << line << "\n" }
      end
      # Fidelity: a modified file without a trailing newline must stay that
      # way after the patch is applied.
      str << "\\ No newline at end of file\n" unless modified.ends_with?('\n')
    end
    body
  end

  private def self.write_lines(target : Path, lines : Array(String), newline : Bool) : Nil
    content = lines.join('\n')
    content += '\n' if newline && !content.empty?
    # Write to a temp file and rename: a direct write would truncate through
    # the hardlink the classic strategy uses to share files with the store,
    # dirtying the pristine copy.
    tmp = Path.new("#{target}.zap-patch-tmp")
    ::File.write(tmp, content)
    ::File.rename(tmp, target)
  end

  private def self.walk(dir : Path, acc : Array(String), prefix : String = "") : Nil
    Dir.each_child(dir) do |name|
      path = dir / name
      rel = prefix.empty? ? name : "#{prefix}/#{name}"
      if ::File.directory?(path)
        walk(path, acc, rel)
      else
        acc << rel
      end
    end
  rescue ::File::NotFoundError
    # A directory that disappeared mid-walk; ignore.
  end

  # Applies the hunks of a single file. Hunk positions are 1-based; a start
  # of 0 means inserting before the first line.
  private def self.apply_hunks(hunks : Array(Hunk), original_lines : Array(String), path : String) : Array(String)
    result = [] of String
    cursor = 0
    hunks.each do |hunk|
      position = Math.max(0, hunk.old_start - 1)
      raise "Cannot apply patch: overlapping hunks in #{path}" if position < cursor
      (cursor...position).each { |i| result << original_lines[i] }
      cursor = position
      hunk.lines.each do |line|
        case line[0]?
        when ' ', '-'
          expected = line[1..]
          actual = original_lines[cursor]?
          raise "Cannot apply patch: context mismatch in #{path} at line #{cursor + 1}" unless actual == expected
          result << expected if line[0]? == ' '
          cursor += 1
        when '+'
          result << line[1..]
        end
      end
    end
    (cursor...original_lines.size).each { |i| result << original_lines[i] }
    result
  end

  # Parses a git-style unified diff into file sections.
  private def self.parse(text : String) : Array(FileSection)
    sections = [] of FileSection
    current : FileSection? = nil
    current_hunk : Hunk? = nil

    text.each_line do |raw|
      line = raw.chomp('\n')
      if line.starts_with?("@@ ")
        if hunk = current_hunk
          push_hunk(current, hunk)
        end
        current_hunk = parse_hunk_header(line)
      elsif line.starts_with?("--- ") || line.starts_with?("+++ ")
        if hunk = current_hunk
          push_hunk(current, hunk)
          current_hunk = nil
        end
        if line.starts_with?("--- ")
          current = FileSection.new
          old_path = line[4..]
          if old_path == "/dev/null"
            current.status = Status::Created
          else
            current.path = strip_prefix(old_path)
          end
          sections << current
        else
          section = current
          raise "Cannot parse patch: +++ without ---" unless section
          new_path = line[4..]
          if new_path == "/dev/null"
            section.status = Status::Deleted
          elsif section.path.empty?
            section.path = strip_prefix(new_path)
          end
        end
      elsif line == "\\ No newline at end of file"
        current.try &.newline = false
      elsif hunk = current_hunk
        hunk.lines << line
      end
    end
    if hunk = current_hunk
      push_hunk(current, hunk)
    end
    sections
  end

  private def self.push_hunk(section : FileSection?, hunk : Hunk) : Nil
    raise "Cannot parse patch: hunk without a file section" unless section
    section.hunks << hunk
  end

  private def self.parse_hunk_header(line : String) : Hunk
    match = line.match(/@@ -(\d+)(?:,(\d+))? \+(\d+)(?:,(\d+))? @@/)
    raise "Cannot parse patch hunk: #{line}" unless match
    Hunk.new(
      match[1].to_i,
      (match[2]? || "1").to_i,
      match[3].to_i,
      (match[4]? || "1").to_i,
      [] of String
    )
  end

  private def self.strip_prefix(path : String) : String
    path.starts_with?("a/") || path.starts_with?("b/") ? path[2..] : path
  end

  # The line diff between two arrays, as hunk body lines (' ', '+', '-').
  private def self.line_diff(original : Array(String), modified : Array(String)) : Array(String)
    n = original.size
    m = modified.size
    if n * m > 16_000_000
      # Too big for the DP table: a full replace (correct, not minimal).
      diff = [] of String
      original.each { |line| diff << "-#{line}" }
      modified.each { |line| diff << "+#{line}" }
      return diff
    end

    lcs = Array.new(n + 1) { Array.new(m + 1, 0) }
    (1..n).each do |i|
      (1..m).each do |j|
        lcs[i][j] = if original[i - 1] == modified[j - 1]
                      lcs[i - 1][j - 1] + 1
                    else
                      Math.max(lcs[i - 1][j], lcs[i][j - 1])
                    end
      end
    end

    diff = [] of String
    i, j = n, m
    while i > 0 && j > 0
      if original[i - 1] == modified[j - 1]
        diff << " #{original[i - 1]}"
        i -= 1
        j -= 1
      elsif lcs[i - 1][j] >= lcs[i][j - 1]
        diff << "-#{original[i - 1]}"
        i -= 1
      else
        diff << "+#{modified[j - 1]}"
        j -= 1
      end
    end
    while i > 0
      diff << "-#{original[i - 1]}"
      i -= 1
    end
    while j > 0
      diff << "+#{modified[j - 1]}"
      j -= 1
    end
    diff.reverse
  end

  # Groups the diff lines into hunks with three context lines around each
  # change, computing the hunk positions.
  private def self.group_hunks(diff : Array(String)) : Array(NamedTuple(old_start: Int32, old_count: Int32, new_start: Int32, new_count: Int32, lines: Array(String)))
    hunks = [] of NamedTuple(old_start: Int32, old_count: Int32, new_start: Int32, new_count: Int32, lines: Array(String))
    changes = [] of Int32
    diff.each_index { |i| changes << i if diff[i][0]? == '+' || diff[i][0]? == '-' }

    idx = 0
    while idx < changes.size
      start = changes[idx]
      stop = start
      while idx + 1 < changes.size && changes[idx + 1] - stop <= 6
        stop = changes[idx + 1]
        idx += 1
      end
      idx += 1
      hunk_start = Math.max(0, start - 3)
      hunk_end = Math.min(diff.size - 1, stop + 3)
      lines = diff[hunk_start..hunk_end]
      hunks << {
        old_start: 1 + diff[0...hunk_start].count { |l| l[0]? != '+' },
        old_count: lines.count { |l| l[0]? != '+' },
        new_start: 1 + diff[0...hunk_start].count { |l| l[0]? != '-' },
        new_count: lines.count { |l| l[0]? != '-' },
        lines:    lines,
      }
    end
    hunks
  end
end
