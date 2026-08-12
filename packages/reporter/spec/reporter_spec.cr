require "spec"
require "../plain"
require "../ndjson"
require "../null"

# The plain reporter is selected for non-TTY output (pipes, logs, CI):
# append-only plain lines, no ANSI sequences or emojis, periodic progress
# and a summary carrying the phase counts and duration.
describe Reporter::Plain do
  it "prints plain progress lines" do
    io = IO::Memory.new
    reporter = Reporter::Plain.new(io)
    # Let the debounce interval elapse so the first counter call runs the
    # action synchronously instead of scheduling it in a timer fiber.
    sleep 60.milliseconds

    ran = false
    reporter.report_resolver_updates do
      reporter.on_resolving_package
      reporter.on_package_resolved
      ran = true
    end
    reporter.stop

    ran.should be_true
    output = io.to_s
    output.should_not contain("\e[")
    output.should contain("Resolving… [0/1]")
  end

  it "carries the phase counts and duration in the summary" do
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
    output.should contain("Done in 1s")
    output.should contain("3 packages resolved")
    output.should contain("1 installed")
    output.should_not contain("\e[")
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
    reporter = Reporter::Ndjson.new(io)
    sleep 60.milliseconds

    reporter.report_resolver_updates do
      reporter.on_resolving_package
      reporter.on_package_resolved
    end
    reporter.info("hi")
    reporter.error(Exception.new("boom"), "at /tmp/x")
    reporter.report_done(1.seconds, 1024_i64, FakeConfig.new)
    reporter.stop

    lines = io.to_s.split('\n').reject(&.empty?)
    lines.each { |line| JSON.parse(line) }
    progress = lines.find { |line| line.includes?(%("resolving")) }
    progress.should_not be_nil
    done = lines.find { |line| line.includes?(%("type":"done")) }
    done.should_not be_nil
    done.not_nil!.should contain(%("resolved":1))
    done.not_nil!.should contain(%("duration_ms":1000))
    lines.any? { |line| line.includes?("boom") }.should be_true
  end
end

struct FakeConfig
  getter print_logs = false
end
