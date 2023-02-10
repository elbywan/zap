require "../reporters/*"

module Zap::Utils
  struct GitUrl
    # See: https://docs.npmjs.com/cli/v9/configuring-npm/package-json#git-urls-as-dependencies
    # <protocol>://[<user>[:<password>]@]<hostname>[:<port>][:][/]<path>[#<commit-ish> | #semver:<semver>]
    GIT_URL_REGEX = /(?:git\+)?(?<protocol>git|ssh|http|https|file):\/\/(?:(?<user>[^:@]+)?(:(?<password>[^@]+))?@)?(?<hostname>[^:\/]+)(:(?<port>\d+))?[\/:](?<path>[^#]+)((?:#semver:(?<semver>[^:]+))|(?:#(?<commitish>[^:]+)))?/

    @url : String
    getter base_url : String
    getter! match : Regex::MatchData
    @protocol : String
    @hostname : String
    @port : Int32?
    @user : String?
    @password : String?
    @path : String?
    @commitish : String?
    @semver : String?
    @reporter : Reporter?

    def initialize(@url : String, @reporter : Reporter? = nil)
      begin
        @match = GIT_URL_REGEX.match(@url).not_nil!
      rescue
        raise "invalid git url: #{@url}"
      end
      @protocol = match["protocol"]
      @hostname = match["hostname"]
      @port = match["port"]?.try(&.to_i)
      @user = match["user"]?
      @password = match["password"]?
      @path = match["path"]?
      @commitish = match["commitish"]?
      @semver = match["semver"]?

      # See: https://git-scm.com/docs/git-clone#_git_urls
      user_pwd_prefix = @user ? @user.not_nil! + (@password ? ":#{@password}" : "") + '@' : ""
      full_host = @hostname + (@port ? ":#{@port}" : "")
      case @protocol
      when "git", "ssh"
        @base_url = %(#{user_pwd_prefix}#{full_host}:/#{@path})
      when "http", "https"
        @base_url = %(#{@protocol}://#{user_pwd_prefix}#{full_host}:/#{@path})
      when "file"
        @base_url = %(#{@protocol}://#{@path})
      else
        raise "invalid git url: #{@url}"
      end
    end

    def clone(dest : (String | Path)? = nil, &) : Nil
      commitish = @commitish
      if semver = @semver
        # List tags and find one matching the specified semver
        commitish = get_tag_for_semver!(semver)
      end

      commitish ||= get_default_branch? || "main"

      # Get the commit hash
      dest ||= yield (get_ref_commit?(commitish) || commitish)
      # Folder already exists, so we can skip cloning
      return if dest.nil?
      self.class.run("git clone --quiet --filter=tree:0 #{@base_url} #{dest}", @reporter)
      self.class.run("git checkout --quiet #{commitish}", @reporter, chdir: dest.to_s)
    end

    def clone(dest : (String | Path)? = nil) : Nil
      clone(dest) { }
    end

    def self.commit_hash(dest : Path | String) : String
      self.run_and_get_output("git rev-parse HEAD", chdir: dest.to_s).chomp
    end

    def get_tag_for_semver!(semver : String) : String
      raw_tags_list = self.class.run_and_get_output("git ls-remote --tags --refs -q #{@base_url}")
      tags = raw_tags_list.each_line.map do |line|
        line.split("\t").last.split("/").last
      end

      semver = Semver.parse(semver)
      tag = nil
      tags.each do |t|
        if semver.valid?(t)
          comparator = Semver::Comparator.parse(t)
          if tag.nil? || tag < comparator
            tag = comparator
          end
        end
      end
      raise "There is no tag matching semver for #{@url}" unless tag
      tag.to_s
    end

    def get_ref_commit?(ref : String) : String?
      self.class.run_and_get_output("git ls-remote #{@base_url} #{ref}").split(/\s+/).first?
    end

    def get_default_branch? : String?
      result = self.class.run_and_get_output("git ls-remote --symref #{@base_url} HEAD")
      result.split("\n")[0]?.try &.split(/\s+/)[1]?.try &.split("/").last?
    end

    def self.run(command : String, reporter : Reporter? = nil, **extra) : Nil
      command_and_args = command.split(/\s+/)
      if reporter
        output = Reporter::ReporterPrependPipe.new(reporter)
      else
        output = Process::Redirect::Inherit
      end
      Zap::Log.debug { "Spawning: #{command_and_args} (#{extra})" }
      status = Process.run(command_and_args[0], **extra, args: command_and_args[1..]? || nil, output: output, error: output)
      unless status.success?
        Fiber.yield
        raise "Command failed: #{command} (#{status.exit_status})"
      end
    end

    def self.run_and_get_output(command, **extra) : String
      command_and_args = command.split(/\s+/)
      stderr = IO::Memory.new
      stdout = IO::Memory.new
      Zap::Log.debug { "Spawning: #{command_and_args} (#{extra})" }
      status = Process.run(command_and_args[0], **extra, args: command_and_args[1..]? || nil, output: stdout, error: stderr)
      unless status.success?
        raise stderr.to_s
      end
      stdout.to_s
    end
  end

  # Attempt to reproduce the gitignore resolution algorithm.
  #
  # I tried to use globs first, but the Crystal implementation does not feel right.
  # Ultimately it seems easier to use regexes.
  struct GitIgnore
    getter rules : Array(Pattern)

    def initialize(patterns : Array(String))
      @rules = patterns.each.map { |pattern| Pattern.new(pattern) }.select(&.regex).to_a
    end

    def initialize(@rules : Array(Pattern))
    end

    # Important: directory entries must end with a slash
    def match?(entry : String) : Bool
      matches = false
      @rules.each do |rule|
        if rule.match?(entry)
          matches = !rule.negated
        end
      end
      matches
    end

    def merge(other : GitIgnore) : GitIgnore
      GitIgnore.new(@rules + other.rules)
    end

    struct Pattern
      getter negated : Bool = false
      getter match_only_directories : Bool = false
      getter regex : Regex? = nil

      # See: https://git-scm.com/docs/gitignore#_pattern_format
      def initialize(pattern : String)
        # Remove trailing space
        pattern = pattern.chomp

        # A blank line matches no files, so it can serve as a separator for readability.
        # A line starting with # serves as a comment.
        if pattern.empty? || pattern.starts_with?("#")
          return
        end

        left_offset = 0
        right_offset = -1

        # An optional prefix "!" which negates the pattern (…)
        if @negated = pattern.starts_with?("!")
          left_offset += 1
        end

        if pattern.starts_with?("/") || pattern.starts_with?("!/")
          left_offset += 1
          relative = true
        end

        # If there is a separator at the end of the pattern then the pattern will only match directories,
        # otherwise the pattern can match both files and directories.
        if @match_only_directories = pattern.ends_with?("/")
          right_offset -= 1
        end

        # Remove the slashes and/or the negation
        pattern = pattern[left_offset..right_offset]

        # If there is a separator at the beginning or middle (or both) of the pattern,
        # then the pattern is relative to the directory level of the particular .gitignore file itself.
        # Otherwise the pattern may also match at any level below the .gitignore level.
        relative ||= pattern.includes?("/")

        # Replace **/ or /**/ or /** or * or ? or special characters
        matchers = /(^\*\*\/|\/\*\*\/|\/\*\*$|\*|\?|\.|\+|\^|\$|\{|\}|\(|\))/
        replacement_map = {
          "**/":  /^([^\/]+\/)*/.to_s,
          "/**/": /(\/([^\/]+\/)*)*/.to_s,
          "/**":  /(\/.*)*$/.to_s,
          "*":    /[^\/]*/,
          "?":    /[^\/]{1}/,
          ".":    "\\.",
          "+":    "\\+",
          "^":    "\\^",
          "$":    "\\$",
          "{":    "\\{",
          "}":    "\\}",
          "(":    "\\(",
          ")":    "\\)",
        }

        @regex = pattern.gsub(matchers, replacement_map).try { |p|
          Regex.new("#{relative ? "^" : ""}#{p}$")
        }
      end

      def match?(entry : String) : Bool
        if entry.ends_with? "/"
          entry = entry[...-1]
        else
          return false if @match_only_directories
        end
        if regex = @regex
          entry.matches?(regex)
        else
          return false
        end
      end
    end
  end
end
