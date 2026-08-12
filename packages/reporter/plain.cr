require "log"
require "utils/timers"
require "utils/misc"
require "semver"
require "concurrency/data_structures/safe_set"
require "./interactive"

# Line-based reporter for non-TTY output (pipes, logs, CI): plain text
# with no ANSI sequences, emojis or cursor movement. Progress prints a
# line every few seconds once a phase is slow, warnings as a plain
# section, and an npm-style summary like a regular command-line tool.
class Reporter::Plain < Reporter::Interactive
  def initialize(@out = STDOUT)
    # A plain reporter means the whole output should be uncolored, including
    # the CLI banner printed around it.
    Colorize.enabled = false
    super
  end

  # The script runners print section headers directly; keep them stern.
  def header(emoji : String, str : String, color = :default) : String
    str
  end

  def report_resolver_updates(& : -> T) : T forall T
    @stopped = false
    @last_progress = Time.monotonic
    @action = -> do
      downloading = @downloading_packages.get
      extra = downloading > 0 ? " • downloading #{@downloaded_packages.get}/#{downloading}" : nil
      progress_line("Resolving", @resolved_packages.get, @resolving_packages.get, extra)
    end
    yield
  ensure
    self.stop
  end

  def report_linker_updates(& : -> T) : T forall T
    @stopped = false
    @last_progress = Time.monotonic
    @action = -> do
      progress_line("Installing", @installed_packages.get, @installing_packages.get)
    end
    yield
  ensure
    self.stop
  end

  def report_builder_updates(& : -> T) : T forall T
    @stopped = false
    @last_progress = Time.monotonic
    @action = -> do
      progress_line("Building", @built_packages.get, @building_packages.get)
    end
    yield
  ensure
    self.stop
  end

  def report_done(realtime, memory, install_config, *, unmet_peers : Hash(String, Hash(Semver::Range, Set(String)))? = nil) : Nil
    @io_lock.synchronize do
      if install_config.print_logs && @logs.size > 0
        @out << "Warnings:" << Shared::Constants::NEW_LINE
        @logs.each { |log| @out << "  • #{log}" << Shared::Constants::NEW_LINE }
        @out << Shared::Constants::NEW_LINE
      end

      if unmet_peers && !unmet_peers.empty?
        @out << "Unmet peers:" << Shared::Constants::NEW_LINE
        unmet_peers.each do |name, versions|
          versions.each do |version, peers|
            @out << "  • #{name}@#{version} (#{peers.join(", ")})" << Shared::Constants::NEW_LINE
          end
        end
        @out << Shared::Constants::NEW_LINE
      end

      # npm-style summary: the counts that matter, nothing else.
      installed = @installed_packages.get
      removed = @removed_packages.size
      duration = realtime ? " in #{Utils::Misc.format_time_span(realtime)}" : ""
      fragments = [] of String
      fragments << "added #{installed} #{noun(installed)}" if installed > 0
      fragments << "removed #{removed} #{noun(removed)}" if removed > 0
      summary = fragments.empty? ? "up to date#{duration}" : "#{fragments.join(" and ")}#{duration}"
      @out << summary << Shared::Constants::NEW_LINE
    end
  end

  private def noun(count : Int32) : String
    count == 1 ? "package" : "packages"
  end

  def info(str : String) : Nil
    @io_lock.synchronize do
      @out << str << Shared::Constants::NEW_LINE
    end
  end

  def warning(error : Exception, location : String? = "") : Nil
    @io_lock.synchronize do
      @out << "Warning#{location.empty? ? "" : " " + location}: #{error.message}" << Shared::Constants::NEW_LINE
    end
  end

  def error(error : Exception, location : String? = "") : Nil
    @io_lock.synchronize do
      @out << "Error#{location.empty? ? "" : " " + location}: #{error.message}" << Shared::Constants::NEW_LINE
    end
  end

  def errors(errors : Array({Exception, String})) : Nil
    @io_lock.synchronize do
      errors.each do |(error, message)|
        @out << "Error: #{message}" << Shared::Constants::NEW_LINE
      end
    end
  end

  private def progress_line(label : String, done : Int32, total : Int32, extra : String? = nil) : Nil
    return unless progress_due?
    output_sync_unless_stopped do
      @out << "#{label}… #{done}/#{total}"
      @out << extra if extra
      @out << Shared::Constants::NEW_LINE
      @out.flush
    end
  end
end
