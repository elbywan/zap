require "./spec_helper"

describe Tui::Input do
  it "parses arrow key escape sequences" do
    input = Tui::Input.new(IO::Memory.new("\e[A\e[B\e[C\e[D"))
    input.next_key.should eq({Tui::Key::Up, 0})
    input.next_key.should eq({Tui::Key::Down, 0})
    input.next_key.should eq({Tui::Key::Right, 0})
    input.next_key.should eq({Tui::Key::Left, 0})
  end

  it "distinguishes a bare escape from a sequence" do
    input = Tui::Input.new(IO::Memory.new("\e"))
    input.next_key.should eq({Tui::Key::Escape, 0})
  end

  it "parses control keys" do
    input = Tui::Input.new(IO::Memory.new(" \r\x03"))
    input.next_key.should eq({Tui::Key::Space, 0})
    input.next_key.should eq({Tui::Key::Enter, 0})
    input.next_key.should eq({Tui::Key::CtrlC, 0})
  end

  it "reports other bytes (letters)" do
    input = Tui::Input.new(IO::Memory.new("a"))
    key, byte = input.next_key
    key.should eq(Tui::Key::Other)
    byte.should eq(0x61)
  end

  it "returns Other for end of input" do
    input = Tui::Input.new(IO::Memory.new(""))
    input.next_key.should eq({Tui::Key::Other, -1})
  end
end
