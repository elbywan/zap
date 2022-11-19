require "../reporter"

module Zap::Utils
  struct GitUrl
    # See: https://docs.npmjs.com/cli/v9/configuring-npm/package-json#git-urls-as-dependencies
    # <protocol>://[<user>[:<password>]@]<hostname>[:<port>][:][/]<path>[#<commit-ish> | #semver:<semver>]
    GIT_URL_REGEX = /(?:git\+)?(?<protocol>git|ssh|http|https|file):\/\/(?:(?<user>[^:@]+)?(:(?<password>[^@]+))?@)?(?<hostname>[^:\/]+)(:(?<port>\d+))?[\/:](?<path>[^#]+)((?:#semver:(?<semver>[^:]+))|(?:#(?<commitish>[^:]+)))?/

    @url : String
    @base_url : String
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
      user_pwd_prefix = @user ? @user.not_nil! + (@password ? ":#{@password}" : "") + "@" : ""
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

    def clone(@dest : Path | String) : Nil
      if @commitish
        # shallow clone and checkout the commit
        self.class.run("git clone --quiet --filter=tree:0 #{@base_url} #{dest}", @reporter)
        self.class.run("git checkout --quiet #{@commitish}", @reporter, chdir: dest)
      elsif semver = @semver
        # list tags and checkout the right one
        # self.run("git clone --no-checkout #{@base_url} #{dest}")
        raw_tags_list = self.class.run_and_get_output("git ls-remote --tags --refs --head -q #{@base_url} #{dest}")
        tags = raw_tags_list.split("\n").map do |line|
          line.split("\t").last.split("/").last
        end
        comparator = Semver::Comparator.parse(semver)
        tag = nil
        tags.each do |t|
          matches = comparator.valid?(Semver::Comparator.parse(t))
          if matches && (tag.nil? || tag < t)
            tag = t
          end
        end
        raise "There is no tag matching semver for #{@url}" unless tag
        self.class.run("git checkout --quiet --filter=tree:0 #{@base_url} #{dest}", @reporter)
        self.class.run("git checkout --quiet #{tag}", @reporter, chdir: dest)
      else
        # clone + checkout the default branch
        self.class.run("git clone --quiet #{@base_url} #{dest}", @reporter)
      end
    end

    def self.commit_hash(dest : Path | String) : String
      self.run_and_get_output("git rev-parse HEAD", chdir: dest).chomp
    end

    def self.run(command : String, reporter : Reporter? = nil, **extra) : Nil
      command_and_args = command.split(/\s+/)
      if reporter
        output = Reporter::ReporterPipe.new(reporter)
      else
        output = Process::Redirect::Inherit
      end
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
      status = Process.run(command_and_args[0], **extra, args: command_and_args[1..]? || nil, output: stdout, error: stderr)
      unless status.success?
        raise stderr.to_s
      end
      stdout.to_s
    end
  end
end
