require "term-cursor"
require "./reporter"
require "../utils/timers"

class Zap::Reporter::Interactive < Zap::Reporter
  @lock = Mutex.new
  @out : IO

  def output
    @out
  end

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
    @cursor = Term::Cursor
    @debounced_update = Utils::Debounce.new(0.01.seconds) do
      update_action
    end
  end

  def on_resolving_package
    @resolving_packages.add(1)
    update()
  end

  def on_package_resolved
    @resolved_packages.add(1)
    update()
  end

  def on_downloading_package
    @downloading_packages.add(1)
    update()
  end

  def on_package_downloaded
    @downloaded_packages.add(1)
    update()
  end

  def on_packing_package
    @packing_packages.add(1)
    update()
  end

  def on_package_packed
    @packed_packages.add(1)
    update()
  end

  def on_package_installed
    @installed_packages.add(1)
    update()
  end

  def on_installing_package
    @installing_packages.add(1)
    update()
  end

  def on_package_built
    @built_packages.add(1)
    update()
  end

  def on_building_package
    @building_packages.add(1)
    update()
  end

  def on_package_added(pkg_key : String)
    @added_packages << pkg_key
  end

  def on_package_removed(pkg_key : String)
    @removed_packages << pkg_key
  end

  def stop
    @lock.synchronize do
      @debounced_update.abort
      @update_channel.send 0 if @written
      Fiber.yield
      @update_channel.close
      if @written
        Colorize.reset(@out)
        @out.flush
        @out.puts ""
      end
      @written = false
    rescue Channel::ClosedError
      # Ignore
    end
  end

  def warning(error : Exception, location : String? = "")
    @lock.synchronize do
      @out << header("⚠️", "Warning", :yellow) + location
      @out << "\n"
      @out << "\n   • #{error.message}".colorize.yellow
      @out << "\n"
      Zap::Log.debug { error.backtrace?.try &.map { |line| "\t#{line}" }.join("\n").colorize.yellow }
    end
  end

  def error(error : Exception, location : String? = "")
    @lock.synchronize do
      @out << header("❌", "Error!", :red) + location
      @out << "\n"
      @out << "\n   • #{error.message}".colorize.red
      @out << "\n"
      Zap::Log.debug { error.backtrace.map { |line| "\t#{line}" }.join("\n").colorize.red }
    end
  end

  def update
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

  def prepend(bytes : Bytes)
    @io_lock.synchronize do
      @out << @cursor.clear_lines(@lines.get, :up)
      @out << String.new(bytes)
      @out << "\n"
      @out.flush
    end
    update
  end

  def prepend(str : String)
    @io_lock.synchronize do
      @out << @cursor.clear_lines(@lines.get, :up)
      @out << str
      @out << "\n"
      @out.flush
    end
    update
  end

  def log(str : String)
    @io_lock.synchronize do
      @logs << str
    end
  end

  def header(emoji, str, color = :default)
    Colorize.reset(@out)
    %( ○ #{emoji} #{str.ljust(25).colorize(color).bright})
  end

  def report_resolver_updates
    @update_channel = Channel(Int32?).new
    spawn(same_thread: true) do
      @lines.set(1)
      loop do
        msg = @update_channel.receive?
        break if msg.nil?
        @io_lock.synchronize do
          @out << @cursor.clear_lines(@lines.get, :up)
          @out << header("🔍", "Resolving…", :yellow) + %([#{@resolved_packages.get}/#{@resolving_packages.get}])
          @lines.set(1)
          if (downloading = @downloading_packages.get) > 0
            @out << "\n"
            @out << header("📡", "Downloading…", :cyan) + %([#{@downloaded_packages.get}/#{downloading}])
            @lines.add(1)
          end
          if (packing = @packing_packages.get) > 0
            @out << "\n"
            @out << header("🎁", "Packing…") + %([#{@packed_packages.get}/#{packing}])
            @lines.add(1)
          end
          @out.flush
        end
      end
    end
  end

  def report_installer_updates
    @update_channel = Channel(Int32?).new
    spawn(same_thread: true) do
      loop do
        msg = @update_channel.receive?
        break if msg.nil?
        next if @installing_packages.get == 0
        @io_lock.synchronize do
          @out << @cursor.clear_line
          @out << header("💽", "Installing…", :magenta) + %([#{@installed_packages.get}/#{@installing_packages.get}])
          @out.flush
        end
      end
    end
  end

  def report_builder_updates
    @update_channel = Channel(Int32?).new
    spawn(same_thread: true) do
      loop do
        msg = @update_channel.receive?
        break if msg.nil?
        @io_lock.synchronize do
          @out << @cursor.clear_line
          @out << header("🏗️", "Building…", :light_red) + %([#{@built_packages.get}/#{@building_packages.get}])
          @out.flush
        end
      end
    end
  end

  def report_done(realtime, memory)
    @io_lock.synchronize do
      if @logs.size > 0
        @out << header("📝", "Logs", :blue)
        @out << "\n"
        separator = "\n   • ".colorize(:default)
        @out << separator
        @out << @logs.join(separator)
        @out << "\n\n"
      end

      # print added / removed packages
      all_packages = @added_packages.map { |pkg_key| {pkg_key, true} } + @removed_packages.map { |pkg_key| {pkg_key, false} }
      if all_packages.size > 0
        @out << header("📦", "Dependencies", :light_yellow) + %(Added: #{@added_packages.size}, Removed: #{@removed_packages.size}).colorize.mode(:dim).to_s
        @out << "\n\n"
        all_packages.map { |pkg_key, added|
          parts = pkg_key.split("@")
          {
            parts[...-1].join("@").colorize.bold.to_s + (" " + parts.last).colorize.dim.to_s,
            added,
          }
        }.sort_by(&.[0]).each do |pkg_key, added|
          if added
            @out << "   #{"＋".colorize.green.bold} #{pkg_key}\n"
          else
            @out << "   #{"－".colorize.red.bold} #{pkg_key}\n"
          end
        end
        @out << "\n"
      end

      @out << header("👌", "Done!", :green)
      if realtime
        @out << ("took " + realtime.total_seconds.humanize + "s • ").colorize.dim
      end
      if memory
        @out << ("total memory allocated " + memory.humanize + "B").colorize.dim
      end
      @out << "\n"
    end
  end

  protected def self.format_pkg_keys(pkgs)
    pkgs.map { |pkg_key|
      parts = pkg_key.split("@")
      parts[...-1].join("@").colorize.bold.to_s + ("@" + parts.last).colorize.dim.to_s
    }.sort!
  end
end
