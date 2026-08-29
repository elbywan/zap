require "./harness"

# The help surfaces against the real binary: -h is the compact help (own
# options only), --help adds the inherited Common/Workspace sections, and
# a bare invocation shows the command list.
describe "zap help", tags: "e2e" do
  it "splits -h (short) from --help (full) for a command" do
    ok, short = E2E.zap(E2E.work, "pack", "-h")
    ok.should be_true
    short.should contain("Usage:")
    short.should contain("--out")
    short.should_not contain("Inherited")

    ok, full = E2E.zap(E2E.work, "pack", "--help")
    ok.should be_true
    full.should contain("Inherited")
    full.should contain("--dir")
  end

  it "shows the command list without inherited options on bare invocation" do
    output = IO::Memory.new
    status = Process.run(E2E.cli, [] of String, chdir: E2E.work, output: output, error: output)
    status.success?.should be_true
    output.to_s.should contain("Commands:")
    output.to_s.should contain("pack")
    output.to_s.should_not contain("Inherited")
  end
end
