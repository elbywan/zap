require "log"
require "utils/timers"
require "utils/misc"
require "semver"
require "concurrency/data_structures/safe_set"
require "./interactive"

# Line-based reporter for non-TTY output (pipes, logs, CI): plain text
# with no ANSI sequences, emojis or cursor movement. Progress prints a
# line every few seconds; the summary carries the phase counts, the
# duration and any errors, like a regular command-line tool.
class Reporter::Plain < Reporter::Interactive
  # Progress cadence for piped output: the first line is immediate, then
  # one line every interval so the log does not drown in frames.
  PROGRESS_INTERVAL = 5.seconds

  @last_progress = Time.monotonic - PROGRESS_INTERVAL

  def initialize(@out = STDOUT)
    # A plain reporter means the whole output should be uncolored, including
    # the CLI banner printed around it.
    Colorize.enabled = false
    super
  end

  def report_resolver_updates(& : -> T) : T forall T
    @stopped = false
    @last_progress = Time.monotonic - PROGRESS_INTERVAL
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
    @last_progress = Time.monotonic - PROGRESS_INTERVAL
    @action = -> do
      progress_line("Installing", @installed_packages.get, @installing_packages.get)
    end
    yield
  ensure
    self.stop
  end

  def report_builder_updates(& : -> T) : T forall T
    @stopped = false
    @last_progress = Time.monotonic - PROGRESS_INTERVAL
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
        @out << "Logs:" << Shared::Constants::NEW_LINE
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

      all_packages = @added_packages.map { |pkg_key| {pkg_key, true} } + @removed_packages.map { |pkg_key| {pkg_key, false} }
      if all_packages.size > 0
        @out << "Added: #{@added_packages.size}, Removed: #{@removed_packages.size}" << Shared::Constants::NEW_LINE
        all_packages.sort_by(&.[0]).each do |pkg_key, added|
          @out << "  #{added ? "+" : "-"} #{pkg_key}" << Shared::Constants::NEW_LINE
        end
        @out << Shared::Constants::NEW_LINE
      end

      @out << "Done in #{Utils::Misc.format_time_span(realtime)} • #{@resolved_packages.get} packages resolved"
      @out << " • #{@installed_packages.get} installed" if @installed_packages.get > 0
      @out << Shared::Constants::NEW_LINE
    end
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
    return unless progress_tick
    output_sync_unless_stopped do
      @out << "#{label}… [#{done}/#{total}]"
      @out << extra if extra
      @out << Shared::Constants::NEW_LINE
      @out.flush
    end
  end

  private def progress_tick : Bool
    return false unless Time.monotonic - @last_progress > PROGRESS_INTERVAL
    @last_progress = Time.monotonic
    true
  end
end
