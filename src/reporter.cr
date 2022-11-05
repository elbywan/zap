require "term-cursor"

class Zap::Reporter
  @lock = Mutex.new

  def initialize(@out = STDOUT)
    @resolving_packages = Atomic(Int32).new(0)
    @resolved_packages = Atomic(Int32).new(0)
    @downloading_packages = Atomic(Int32).new(0)
    @downloaded_packages = Atomic(Int32).new(0)
    @installing_packages = Atomic(Int32).new(0)
    @installed_packages = Atomic(Int32).new(0)
    @update_channel = Channel(Int32?).new
    @cursor = Term::Cursor
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

  def on_package_installed
    @installed_packages.add(1)
    update()
  end

  def on_installing_package
    @installing_packages.add(1)
    update()
  end

  def stop
    @lock.synchronize do
      @update_channel.close
      @out.puts ""
    end
  end

  def update
    @lock.synchronize do
      @update_channel.send 0 unless @update_channel.closed?
    end
  end

  def header(emoji, str, color = nil)
    %( ○ #{emoji} #{str.ljust(25).colorize(color).mode(:bright)})
  end

  def report_resolver_updates
    @update_channel = Channel(Int32?).new
    spawn(same_thread: true) do
      lines = 1
      loop do
        msg = @update_channel.receive?
        break if msg.nil?
        @out << @cursor.clear_lines(lines, :up)
        @out << header("🔍", "Resolving…", :yellow) + %([#{@resolved_packages.get}/#{@resolving_packages.get}])
        if (downloading = @downloading_packages.get) > 0
          @out << "\n"
          @out << header("🛰️", "Downloading…", :cyan) + %([#{@downloaded_packages.get}/#{downloading}])
          lines = 2
        else
          lines = 1
        end
        @out.flush
      end
    end
  end

  def report_installer_updates
    @update_channel = Channel(Int32?).new
    spawn(same_thread: true) do
      loop do
        msg = @update_channel.receive?
        break if msg.nil?
        @out << @cursor.clear_line
        @out << header("💾", "Installing…", :magenta) + %([#{@installed_packages.get}/#{@installing_packages.get}])
        @out.flush
      end
    end
  end

  def report_done(realtime, memory)
    @out << header("👌", "Done!", :green)
    if realtime
      @out << ("took " + realtime.total_seconds.humanize + "s • ").colorize.mode(:dim)
    end
    if memory
      @out << ("memory usage " + memory.humanize + "B").colorize.mode(:dim)
    end
    @out.puts
  end
end
