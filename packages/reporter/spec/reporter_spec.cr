require "spec"
require "../plain"
require "../ndjson"
require "../null"

# The plain reporter is selected for non-TTY output (pipes, logs, CI):
# append-only plain lines, no ANSI sequences or emojis, progress only once
# a phase has been running for a while, and an npm-style summary.
# Shrink the progress cadence so the specs do not have to wait 5s.
private class FastPlain < Reporter::Plain
  def self.progress_interval : Time::Span
    10.milliseconds
  end
end

private class FastNdjson < Reporter::Ndjson
  def self.progress_interval : Time::Span
    10.milliseconds
  end
end

describe Reporter::Plain do
  it "prints a progress line once a phase is slow" do
    io = IO::Memory.new
    reporter = FastPlain.new(io)
    # Let the debounce interval elapse so the first counter call runs the
    # action synchronously instead of scheduling it in a timer fiber.
    sleep 60.milliseconds

    ran = false
    reporter.report_resolver_updates do
      sleep 20.milliseconds
      reporter.on_resolving_package
      reporter.on_package_resolved
      ran = true
    end
    reporter.stop

    ran.should be_true
    output = io.to_s
    output.should_not contain("\e[")
    output.should contain("Resolving… 0/1")
  end

  it "prints an npm-style summary and warnings" do
    io = IO::Memory.new
    reporter = Reporter::Plain.new(io)

    reporter.log("unsupported engine for foo@1.0.0")
    reporter.report_resolver_updates do
      3.times { reporter.on_resolving_package }
      3.times { reporter.on_package_resolved }
      reporter.on_linking_package
      reporter.on_package_linked
    end
    reporter.report_done(1.seconds, 1024_i64, FakeConfig.new, unmet_peers: nil)
    reporter.stop

    output = io.to_s
    output.should contain("Warnings:")
    output.should contain("unsupported engine for foo@1.0.0")
    output.should contain("added 1 package in 1s")
    output.should_not contain("packages resolved")
    output.should_not contain("\e[")
  end

  it "prints 'up to date' when nothing changed" do
    io = IO::Memory.new
    reporter = Reporter::Plain.new(io)
    reporter.report_done(1.seconds, 1024_i64, FakeConfig.new, unmet_peers: nil)
    reporter.stop

    io.to_s.should contain("up to date in 1s")
  end

  it "reports unmet peers" do
    io = IO::Memory.new
    reporter = Reporter::Plain.new(io)
    unmet = {"app" => {Semver.parse("*") => Set{"react"}}}
    reporter.report_done(1.seconds, 1024_i64, FakeConfig.new, unmet_peers: unmet)
    reporter.stop

    output = io.to_s
    output.should contain("Unmet peers:")
    output.should contain("(react)")
  end

  it "prints a stern section header" do
    io = IO::Memory.new
    reporter = Reporter::Plain.new(io)
    reporter.header("🪝", "Hooks").should eq("Hooks")
  end

  it "combines added and removed in the summary" do
    io = IO::Memory.new
    reporter = Reporter::Plain.new(io)
    reporter.report_linker_updates do
      reporter.on_linking_package
      reporter.on_package_linked
    end
    reporter.on_package_removed("foo@1.0.0")
    reporter.on_package_removed("bar@2.0.0")
    reporter.report_done(1.seconds, 1024_i64, FakeConfig.new)
    reporter.stop

    io.to_s.should contain("added 1 package and removed 2 packages in 1s")
  end

  it "prints errors" do
    io = IO::Memory.new
    reporter = Reporter::Plain.new(io)
    reporter.error(Exception.new("boom"), "at /tmp/x")
    reporter.stop

    output = io.to_s
    output.should contain("Error at /tmp/x: boom")
    output.should_not contain("\e[")
  end
end

describe Reporter::Ndjson do
  it "emits one JSON object per line" do
    io = IO::Memory.new
    reporter = FastNdjson.new(io)
    sleep 60.milliseconds

    reporter.report_resolver_updates do
      sleep 20.milliseconds
      reporter.on_resolving_package
      reporter.on_package_resolved
    end
    reporter.info("hi")
    reporter.error(Exception.new("boom"), "at /tmp/x")
    reporter.report_done(1.seconds, 1024_i64, FakeConfig.new)
    reporter.stop

    lines = io.to_s.split('\n').reject(&.empty?)
    lines.each { |line| JSON.parse(line) }
    # Script output and hook headers are dropped so the stream stays JSON.
    reporter.output << "corrupt"
    reporter.output_sync { |io| io << "corrupt" }
    reporter.prepend("corrupt".to_slice)
    io.to_s.split('\n').reject(&.empty?).each { |line| JSON.parse(line) }
    progress = lines.find { |line| line.includes?(%("resolving")) }
    progress.should_not be_nil
    done = lines.find { |line| line.includes?(%("type":"done")) }
    done.should_not be_nil
    done.not_nil!.should contain(%("resolved":1))
    done.not_nil!.should contain(%("duration_ms":1000))
    lines.any? { |line| line.includes?("boom") }.should be_true
  end

  it "flushes accumulated warnings as events" do
    io = IO::Memory.new
    reporter = Reporter::Ndjson.new(io)
    reporter.log("unsupported engine for foo@1.0.0")
    reporter.report_done(1.seconds, 1024_i64, FakeConfig.new)
    reporter.stop

    lines = io.to_s.split('\n').reject(&.empty?)
    warning = lines.find { |line| line.includes?(%("type":"warning")) }
    warning.should_not be_nil
    warning.not_nil!.should contain("unsupported engine")
  end
end

struct FakeConfig
  getter print_logs = true
end
