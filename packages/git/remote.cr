require "log"

class Git::Remote
  Log = ::Log.for("zap.git.remote")

  # See: https://docs.npmjs.com/cli/v9/configuring-npm/package-json#git-urls-as-dependencies
  # <protocol>://[<user>[:<password>]@]<hostname>[:<port>][:][/]<path>[#<commit-ish> | #semver:<semver>]
  GIT_URL_REGEX = /(?:git\+)?(?<protocol>git|ssh|http|https|file):\/\/(?:(?<user>[^:@]+)?(:(?<password>[^@]+))?@)?(?<hostname>[^:\/]+)(:(?<port>\d+))?[\/:](?<path>[^#]+)((?:#semver:(?<semver>[^:]+))|(?:#(?<commitish>[^:]+)))?/

  getter url : String
  getter base_url : String
  getter! match : Regex::MatchData
  getter protocol : String
  getter hostname : String
  getter port : Int32?
  getter user : String?
  getter password : String?
  getter path : String?
  getter commitish : String?
  getter semver : String?
  @output : Process::Stdio?
  getter resolved_commitish : String do
    commitish = @commitish
    if semver = @semver
      # List tags and find one matching the specified semver
      commitish = get_tag_for_semver!(semver)
    end

    commitish || get_default_branch? || "main"
  end

  getter commitish_hash : String do
    ref_commit = get_ref_commit?(resolved_commitish)
    if !ref_commit || ref_commit.empty?
      resolved_commitish
    else
      ref_commit
    end
  end

  getter key : String do
    "git+#{base_url}##{commitish_hash}"
  end

  getter short_key : String do
    "#{@hostname + (@port ? ":#{@port}" : "")}/#{@path}##{commitish_hash}"
  end

  def initialize(@url : String, @output : Process::Stdio? = nil)
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
    when "git"
      @base_url = %(#{@protocol}://#{full_host}:#{@path})
    when "http", "https", "ssh"
      @base_url = %(#{@protocol}://#{user_pwd_prefix}#{full_host}/#{@path})
    when "file"
      @base_url = %(#{@protocol}://#{@path})
    else
      raise "invalid git url: #{@url}"
    end
  end

  def clone(dest : (String | Path) = nil) : Nil
    temp_dest = dest.to_s + ".tmp"
    FileUtils.rm_rf(temp_dest) if ::File.exists?(temp_dest)
    self.class.run("git clone --quiet --filter=tree:0 #{@base_url} #{temp_dest}", @output)
    self.class.run("git checkout --quiet #{resolved_commitish}", @output, chdir: temp_dest.to_s)
    ::File.rename(temp_dest, dest)
  end

  def self.head_commit_hash(dest : Path | String) : String
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
      if semver.satisfies?(t)
        comparator = Semver::Version.parse(t)
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
    result.split(Shared::Constants::NEW_LINE)[0]?.try &.split(/\s+/)[1]?.try &.split("/").last?
  end

  def self.run(command : String, stdio : Process::Stdio? = nil, **extra) : Nil
    command_and_args = command.split(/\s+/)
    output = stdio || Process::Redirect::Inherit
    Log.debug { "Spawning: #{command_and_args} (#{extra})" }
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
    Log.debug { "Spawning: #{command_and_args} (#{extra})" }
    status = Process.run(command_and_args[0], **extra, args: command_and_args[1..]? || nil, output: stdout, error: stderr)
    unless status.success?
      raise stderr.to_s
    end
    stdout.to_s
  end
end
