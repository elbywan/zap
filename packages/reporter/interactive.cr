require "log"
require "utils/timers"
require "semver"
require "./reporter"

class Reporter::Interactive < Reporter
  @out : IO
  @lines = Atomic(Int32).new(0)
  @written : Bool = false
  @logs : Array(String) = [] of String
  @action : (-> Void) | Nil = nil
  @stopped : Bool = false

  def initialize(@out = STDOUT)
    @resolving_packages = Atomic(Int32).new(0)
    @resolved_packages = Atomic(Int32).new(0)
    @downloading_packages = Atomic(Int32).new(0)
    @downloaded_packages = Atomic(Int32).new(0)
    @packing_packages = Atomic(Int32).new(0)
    @packed_packages = Atomic(Int32).new(0)
    @installing_packages = Atomic(Int32).new(0)
    @installed_packages = Atomic(Int32).new(0)
    @building_packages = Atomic(Int32).new(0)
    @built_packages = Atomic(Int32).new(0)
    @added_packages = Concurrency::SafeSet(String).new
    @removed_packages = Concurrency::SafeSet(String).new
    @debounced_update = Utils::Debounce.new(0.05.seconds) do
      @action.try &.call
    end
  end

  # In-house ANSI helpers (replaces the term-cursor shard).
  private def clear_lines_up(n : Int32) : String
    String.build do |str|
      n.times do |i|
        str << "\e[2K\r"
        str << "\e[1A" unless i == n - 1
      end
    end
  end

  def output : IO
    @out
  end

  def output_sync(&block : IO ->) : Nil
    @io_lock.synchronize do
      block.call(@out)
    end
  end

  def output_sync_unless_stopped(&block : IO ->) : Nil
    @io_lock.synchronize do
      return nil if @stopped
      @written = true
      return block.call(@out)
    end
  end

  def on_resolving_package : Nil
    @resolving_packages.add(1)
    @debounced_update.call
  end

  def on_package_resolved : Nil
    @resolved_packages.add(1)
    @debounced_update.call
  end

  def on_downloading_package : Nil
    @downloading_packages.add(1)
    @debounced_update.call
  end

  def on_package_downloaded : Nil
    @downloaded_packages.add(1)
    @debounced_update.call
  end

  def on_packing_package : Nil
    @packing_packages.add(1)
    @debounced_update.call
  end

  def on_package_packed : Nil
    @packed_packages.add(1)
    @debounced_update.call
  end

  def on_package_linked : Nil
    @installed_packages.add(1)
    @debounced_update.call
  end

  def on_linking_package : Nil
    @installing_packages.add(1)
    @debounced_update.call
  end

  def on_package_built : Nil
    @built_packages.add(1)
    @debounced_update.call
  end

  def on_building_package : Nil
    @building_packages.add(1)
    @debounced_update.call
  end

  def on_package_added(pkg_key : String) : Nil
    @added_packages << pkg_key
  end

  def on_package_removed(pkg_key : String) : Nil
    @removed_packages << pkg_key
  end

  def stop : Nil
    @debounced_update.abort
    @action.try &.call if @written
    @io_lock.synchronize {
      @stopped = true
      @out << Shared::Constants::NEW_LINE if @written
      @written = false
      @lines.set(0)
    }
  end

  def info(str : String) : Nil
    @io_lock.synchronize do
      @out << %( 💡 #{str.colorize(:blue)}) << Shared::Constants::NEW_LINE
    end
  end

  def warning(error : Exception, location : String? = "") : Nil
    @io_lock.synchronize do
      @out << header("⚠️", "Warning", :yellow) + location
      @out << Shared::Constants::NEW_LINE
      @out << "\n  • #{error.message}".colorize.yellow
      @out << Shared::Constants::NEW_LINE
      Log.debug { error.backtrace?.try &.map { |line| "\t#{line}" }.join(Shared::Constants::NEW_LINE).colorize.yellow }
    end
  end

  def error(error : Exception, location : String? = "") : Nil
    @io_lock.synchronize do
      @out << Shared::Constants::NEW_LINE
      @out << header("❌", "Error(s):", :red) + location << Shared::Constants::NEW_LINE << Shared::Constants::NEW_LINE
      @out << " • #{error.message.try &.split(Shared::Constants::NEW_LINE).join("\n   ")}" << Shared::Constants::NEW_LINE
      @out << Shared::Constants::NEW_LINE
      Log.debug { error.backtrace.map { |line| "\t#{line}" }.join(Shared::Constants::NEW_LINE).colorize.red }
    end
  end

  def errors(errors : Array({Exception, String})) : Nil
    @io_lock.synchronize do
      @out << Shared::Constants::NEW_LINE
      @out << header("❌", "Error(s):", :red) << Shared::Constants::NEW_LINE << Shared::Constants::NEW_LINE
      errors.each do |(error, message)|
        @out << " • #{message.try &.split(Shared::Constants::NEW_LINE).join("\n   ")}" << Shared::Constants::NEW_LINE
        Log.debug { error.backtrace.map { |line| "\t#{line}" }.join(Shared::Constants::NEW_LINE).colorize.red }
      end
      @out << Shared::Constants::NEW_LINE
    end
  end

  def prepend(bytes : Bytes) : Nil
    @io_lock.synchronize do
      @out << clear_lines_up(@lines.get)
      @out << String.new(bytes)
      @out << Shared::Constants::NEW_LINE
      @out.flush
    end
    @debounced_update.call
  end

  def prepend(str : String) : Nil
    @io_lock.synchronize do
      @out << clear_lines_up(@lines.get)
      @out << str
      @out << Shared::Constants::NEW_LINE
      @out.flush
    end
    @debounced_update.call
  end

  def log(str : String) : Nil
    @io_lock.synchronize do
      @logs << str
    end
  end

  def report_resolver_updates(& : -> T) : T forall T
    @stopped = false
    @lines.set(1)
    resolving_header = header("🔍", "Resolving…", :yellow)
    downloading_header = header("📡", "Downloading…", :cyan)
    packing_header = header("🎁", "Packing…")
    @action = -> do
      output = String.build do |str|
        str << clear_lines_up(@lines.get)
        str << resolving_header
        str << %([#{@resolved_packages.get}/#{@resolving_packages.get}])
        @lines.set(1)
        if (downloading = @downloading_packages.get) > 0
          str << Shared::Constants::NEW_LINE
          str << downloading_header
          str << %([#{@downloaded_packages.get}/#{downloading}])
          @lines.add(1)
        end
        if (packing = @packing_packages.get) > 0
          str << Shared::Constants::NEW_LINE
          str << packing_header
          str << %([#{@packed_packages.get}/#{packing}])
          @lines.add(1)
        end
      end
      output_sync_unless_stopped do
        @out << output
        @out.flush
      ensure
        STDIN.cooked! if STDIN.tty?
      end
    end
    yield
  ensure
    self.stop
  end

  def report_linker_updates(& : -> T) : T forall T
    @stopped = false
    installing_header = header("💽", "Installing…", :magenta)
    @action = -> do
      if @installing_packages.get > 0
        output_sync_unless_stopped do
          @out << "\e[2K\r"
          @out << installing_header
          @out << %([#{@installed_packages.get}/#{@installing_packages.get}])
          @out.flush
        end
      end
    end
    yield
  ensure
    self.stop
  end

  def report_builder_updates(& : -> T) : T forall T
    @stopped = false
    building_header = header("🧱", "Building…", :light_red)
    @action = -> do
      output_sync_unless_stopped do
        @out << "\e[2K\r"
        @out << building_header
        @out << %([#{@built_packages.get}/#{@building_packages.get}])
        @out.flush
      end
    end
    yield
  ensure
    self.stop
  end

  def report_done(realtime, memory, install_config, *, unmet_peers : Hash(String, Hash(Semver::Range, Set(String)))? = nil) : Nil
    @io_lock.synchronize do
      if install_config.print_logs && @logs.size > 0
        @out << header("📝", "Logs", :blue)
        @out << Shared::Constants::NEW_LINE
        separator = "\n   • ".colorize(:default)
        @out << separator
        @out << @logs.join(separator)
        @out << "\n\n"
      end

      # print missing peers
      if unmet_peers && !unmet_peers.empty?
        @out << header("❗️", "Unmet Peers", :light_red)
        @out << Shared::Constants::NEW_LINE
        separator = "\n   • ".colorize(:red)
        @out << separator
        @out << unmet_peers.to_a.flat_map { |name, versions|
          versions.map { |version, peers| {"#{name}@#{version}", name, version, peers} }
        }.sort_by(&.[0]).map { |key, name, version, peers|
          "#{name}@#{version} #{"(#{peers.join(", ")})".colorize.dim}"
        }.join(separator)

        incompatible_versions = Array({String, String}).new
        install_versions = unmet_peers.to_a.map do |name, versions|
          install_version = versions.reduce(Semver::Range.new) do |acc, (version, peers)|
            acc.try &.intersection?(version)
          end

          if install_version
            %("#{name}@#{install_version.reduce}")
          else
            incompatible_versions << {name, versions.map { |v, peers| "     #{v} #{"(#{peers.join(", ")})".colorize.dim}" }.join(Shared::Constants::NEW_LINE)}
            nil
          end
        end.compact!

        @out << "\n\n"

        unless incompatible_versions.empty?
          @out << "   ⚠️ These packages have incompatible peer dependencies versions: \n".colorize.red.bold
          @out << separator
          @out << incompatible_versions.map { |name, versions| "#{name.colorize.red}\n#{versions}" }.join(separator)
          @out << "\n\n"
        end

        unless install_versions.empty?
          @out << "To install the missing peer dependencies, run:\n".colorize.bold
          @out << "zap install #{install_versions.join(" ")}".colorize.bold.cyan
          @out << "\n\n"
        end
      end

      # print added / removed packages
      all_packages = @added_packages.map { |pkg_key| {pkg_key, true} } + @removed_packages.map { |pkg_key| {pkg_key, false} }
      if all_packages.size > 0
        @out << header("📦", "Dependencies", :light_yellow)
        @out << "Added: #{@added_packages.size}, Removed: #{@removed_packages.size}".colorize.mode(:dim)
        @out << "\n\n"
        all_packages.map { |pkg_key, added|
          parts = pkg_key.split('@')
          {
            "#{parts[...-1].join('@').colorize.bold} #{parts.last.colorize.dim}",
            added,
          }
        }.sort_by(&.[0]).each do |pkg_key, added|
          if added
            @out << "   #{"＋".colorize.green.bold} #{pkg_key}\n"
          else
            @out << "   #{"－".colorize.red.bold} #{pkg_key}\n"
          end
        end
        @out << Shared::Constants::NEW_LINE
      end

      @out << header("👌", "Done!", :green)
      if realtime
        @out << "took #{Utils::Misc.format_time_span(realtime)} • ".colorize.dim
      end
      if memory
        @out << "heap size #{GC.stats.heap_size.humanize}B • total memory allocated #{memory.humanize}B".colorize.dim
      end
      @out << Shared::Constants::NEW_LINE
    end
  end

  def header(emoji : String, str : String, color = :default) : String
    %( ○ #{emoji} #{str.ljust(25).colorize(color).bright})
  end

  protected def self.format_pkg_keys(pkgs)
    pkgs.map { |pkg_key|
      parts = pkg_key.split('@')
      "#{parts[...-1].join('@').colorize.bold}#{("@#{parts.last}").colorize.dim}"
    }.sort!
  end
end
