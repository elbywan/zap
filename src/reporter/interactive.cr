require "term-cursor"
require "./reporter"
require "../utils/timers"

class Zap::Reporter::Interactive < Zap::Reporter
  @lock = Mutex.new
  @out : IO
  @lines = Atomic(Int32).new(0)
  @written : Bool = false
  @logs : Array(String) = [] of String

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
    @added_packages = SafeSet(String).new
    @removed_packages = SafeSet(String).new
    @update_channel = Channel(Int32?).new
    @stop_channel = Channel(Nil).new
    @cursor = Term::Cursor
    @debounced_update = Utils::Debounce.new(0.05.seconds) do
      update_action
    end
  end

  def output : IO
    @out
  end

  def output_sync(&block : IO ->) : Nil
    @lock.synchronize do
      yield @out
    end
  end

  def on_resolving_package : Nil
    @resolving_packages.add(1)
    update()
  end

  def on_package_resolved : Nil
    @resolved_packages.add(1)
    update()
  end

  def on_downloading_package : Nil
    @downloading_packages.add(1)
    update()
  end

  def on_package_downloaded : Nil
    @downloaded_packages.add(1)
    update()
  end

  def on_packing_package : Nil
    @packing_packages.add(1)
    update()
  end

  def on_package_packed : Nil
    @packed_packages.add(1)
    update()
  end

  def on_package_installed : Nil
    @installed_packages.add(1)
    update()
  end

  def on_installing_package : Nil
    @installing_packages.add(1)
    update()
  end

  def on_package_built : Nil
    @built_packages.add(1)
    update()
  end

  def on_building_package : Nil
    @building_packages.add(1)
    update()
  end

  def on_package_added(pkg_key : String) : Nil
    @added_packages << pkg_key
  end

  def on_package_removed(pkg_key : String) : Nil
    @removed_packages << pkg_key
  end

  def stop : Nil
    @lock.synchronize do
      @debounced_update.abort
      @update_channel.send 0 if @written
      Fiber.yield
      @update_channel.close
      @stop_channel.receive
      @written = false
      @lines.set(0)
    rescue Channel::ClosedError
      # Ignore
    end
  end

  def info(str : String) : Nil
    @lock.synchronize do
      @out << %( ℹ #{str.colorize(:blue)}) << NEW_LINE
    end
  end

  def warning(error : Exception, location : String? = "") : Nil
    @lock.synchronize do
      @out << header("⚠️", "Warning", :yellow) + location
      @out << NEW_LINE
      @out << "\n  • #{error.message}".colorize.yellow
      @out << NEW_LINE
      Zap::Log.debug { error.backtrace?.try &.map { |line| "\t#{line}" }.join(NEW_LINE).colorize.yellow }
    end
  end

  def error(error : Exception, location : String? = "") : Nil
    @lock.synchronize do
      @out << NEW_LINE
      @out << header("❌", "Error(s):", :red) + location << NEW_LINE << NEW_LINE
      @out << " • #{error.message.try &.split(NEW_LINE).join("\n   ")}" << NEW_LINE
      @out << NEW_LINE
      Zap::Log.debug { error.backtrace.map { |line| "\t#{line}" }.join(NEW_LINE).colorize.red }
    end
  end

  def errors(errors : Array({Exception, String})) : Nil
    @lock.synchronize do
      @out << NEW_LINE
      @out << header("❌", "Error(s):", :red) << NEW_LINE << NEW_LINE
      errors.each do |(error, message)|
        @out << " • #{message.try &.split(NEW_LINE).join("\n   ")}" << NEW_LINE
        Zap::Log.debug { error.backtrace.map { |line| "\t#{line}" }.join(NEW_LINE).colorize.red }
      end
      @out << NEW_LINE
    end
  end

  def prepend(bytes : Bytes) : Nil
    @io_lock.synchronize do
      @out << @cursor.clear_lines(@lines.get, :up)
      @out << String.new(bytes)
      @out << NEW_LINE
      @out.flush
    end
    update
  end

  def prepend(str : String) : Nil
    @io_lock.synchronize do
      @out << @cursor.clear_lines(@lines.get, :up)
      @out << str
      @out << NEW_LINE
      @out.flush
    end
    update
  end

  def log(str : String) : Nil
    @io_lock.synchronize do
      @logs << str
    end
  end

  def report_resolver_updates(& : -> T) : T forall T
    @update_channel = Channel(Int32?).new
    Utils::Thread.worker do
      @lines.set(1)
      resolving_header = header("🔍", "Resolving…", :yellow)
      downloading_header = header("📡", "Downloading…", :cyan)
      packing_header = header("🎁", "Packing…")
      loop do
        msg = @update_channel.receive?
        if msg.nil?
          @io_lock.synchronize { @out << NEW_LINE }
          @stop_channel.send nil
          break
        end
        output = String.build do |str|
          str << @cursor.clear_lines(@lines.get, :up)
          str << resolving_header
          str << %([#{@resolved_packages.get}/#{@resolving_packages.get}])
          @lines.set(1)
          if (downloading = @downloading_packages.get) > 0
            str << NEW_LINE
            str << downloading_header
            str << %([#{@downloaded_packages.get}/#{downloading}])
            @lines.add(1)
          end
          if (packing = @packing_packages.get) > 0
            str << NEW_LINE
            str << packing_header
            str << %([#{@packed_packages.get}/#{packing}])
            @lines.add(1)
          end
        end
        @io_lock.synchronize do
          @out << output
          @out.flush
        ensure
          STDIN.cooked! if STDIN.tty?
        end
      end
    end
    yield
  ensure
    self.stop
  end

  def report_installer_updates(& : -> T) : T forall T
    @update_channel = Channel(Int32?).new
    Utils::Thread.worker do
      installing_header = header("💽", "Installing…", :magenta)
      loop do
        msg = @update_channel.receive?
        if msg.nil?
          @io_lock.synchronize { @out << NEW_LINE }
          @stop_channel.send nil
          break
        end
        next if @installing_packages.get == 0
        @io_lock.synchronize do
          @out << @cursor.clear_line
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
    @update_channel = Channel(Int32?).new
    building_header = header("🧱", "Building…", :light_red)
    Utils::Thread.worker do
      loop do
        msg = @update_channel.receive?
        if msg.nil?
          @io_lock.synchronize { @out << NEW_LINE }
          @stop_channel.send nil
          break
        end
        @io_lock.synchronize do
          @out << @cursor.clear_line
          @out << building_header
          @out << %([#{@built_packages.get}/#{@building_packages.get}])
          @out.flush
        end
      end
    end
    yield
  ensure
    self.stop
  end

  def report_done(realtime, memory, install_config, *, unmet_peers : Hash(String, Hash(String, Set(String)))? = nil) : Nil
    @io_lock.synchronize do
      if install_config.print_logs && @logs.size > 0
        @out << header("📝", "Logs", :blue)
        @out << NEW_LINE
        separator = "\n   • ".colorize(:default)
        @out << separator
        @out << @logs.join(separator)
        @out << "\n\n"
      end

      # print missing peers
      if unmet_peers && !unmet_peers.empty?
        @out << header("❗️", "Unmet Peers", :light_red)
        @out << NEW_LINE
        separator = "\n   • ".colorize(:red)
        @out << separator
        @out << unmet_peers.to_a.flat_map { |name, versions|
          versions.map { |version, peers| {"#{name}@#{version}", name, version, peers} }
        }.sort_by(&.[0]).map { |key, name, version, peers|
          "#{name}@#{version} #{"(#{peers.join(", ")})".colorize.dim}"
        }.join(separator)

        incompatible_versions = Array({String, String}).new
        install_versions = unmet_peers.to_a.map do |name, versions|
          install_version = versions.reduce(Utils::Semver::Range.new) do |acc, (version, peers)|
            acc.try &.intersection?(Utils::Semver.parse(version))
          end

          if install_version
            %("#{name}@#{install_version}")
          else
            incompatible_versions << {name, versions.map { |v, _| "     #{v}" }.join(NEW_LINE)}
            nil
          end
        end.compact!

        @out << "\n\n"

        unless incompatible_versions.empty?
          @out << "   ⚠️ These packages have incompatible peer dependencies versions: \n".colorize.red.bold
          @out << separator
          @out << incompatible_versions.map { |name, versions| "#{name.colorize.red}:\n#{versions}" }.join(separator)
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
        @out << NEW_LINE
      end

      @out << header("👌", "Done!", :green)
      if realtime
        @out << "took #{Utils::Various.format_time_span(realtime)} • ".colorize.dim
      end
      if memory
        @out << "heap size #{GC.stats.heap_size.humanize}B • total memory allocated #{memory.humanize}B".colorize.dim
      end
      @out << NEW_LINE
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

  private def update
    @debounced_update.call
  end

  private def update_action
    @lock.synchronize do
      return if @update_channel.closed?
      @written = true
      @update_channel.send 0
    rescue Channel::ClosedError
      # Ignore
    end
  end
end
