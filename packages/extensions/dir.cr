class Dir
  # Yield every child entry in the directory.
  def self.each_child_entry(dirname : Path | String, & : Crystal::System::Dir::Entry ->)
    Dir.open(dirname) do |dir|
      dir.each_child_entry do |file|
        yield file
      end
    end
  end

  # Yield every child entry in the directory.
  def each_child_entry(& : Crystal::System::Dir::Entry ->) : Nil
    excluded = {".", ".."}
    while entry = Crystal::System::Dir.next_entry(@dir, path)
      yield entry unless excluded.includes?(entry.name)
    end
  end

  module Globber
    def self.expand_brace_pattern(pattern : String, expanded) : Array(String)?
      previous_def(pattern, expanded)
    end
  end
end
