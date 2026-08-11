require "./spec_helper"

describe Tui::List do
  it "moves the cursor and clamps at the edges" do
    list = Tui::List.new([Tui::List::Item.new("a"), Tui::List::Item.new("b"), Tui::List::Item.new("c")])
    list.cursor.should eq(0)
    list.move(-1)
    list.cursor.should eq(0)
    list.move(1)
    list.cursor.should eq(1)
    list.move(10)
    list.cursor.should eq(2)
  end

  it "toggles the item under the cursor" do
    list = Tui::List.new([Tui::List::Item.new("a"), Tui::List::Item.new("b")])
    list.toggle
    list.selected.should eq(Set{0})
    list.toggle
    list.selected.should be_empty
  end

  it "toggles between selecting all and none" do
    list = Tui::List.new([Tui::List::Item.new("a"), Tui::List::Item.new("b"), Tui::List::Item.new("c")])
    list.toggle_all
    list.selected.should eq(Set{0, 1, 2})
    list.toggle_all
    list.selected.should be_empty
  end

  it "renders the window with markers and header" do
    list = Tui::List.new([Tui::List::Item.new("a"), Tui::List::Item.new("b")])
    list.toggle
    list.move(1)
    io = IO::Memory.new
    list.render(io, 10)
    output = io.to_s
    output.should contain("Select packages to update")
    output.should contain("[x] a")
    output.should contain("[ ] b")
    output.should contain("> [ ] b") # cursor line
    output.should contain("1 of 2 selected")
  end

  it "scrolls the window to keep the cursor visible" do
    items = (0...20).map { |i| Tui::List::Item.new("pkg#{i}") }
    list = Tui::List.new(items)
    list.move(19)
    io = IO::Memory.new
    list.render(io, 10)
    output = io.to_s
    # The last item is visible and the first is scrolled away.
    output.should contain("pkg19")
    output.should_not contain("pkg0")
  end

  it "returns the selected indices from the selection loop" do
    input = Tui::Input.new(IO::Memory.new(" \e[A \e[B a\r"))
    # a (select all) then enter
    input = Tui::Input.new(IO::Memory.new("a\r"))
    items = [Tui::List::Item.new("x"), Tui::List::Item.new("y")]
    selected = Tui::List.select(items, input, IO::Memory.new)
    selected.should eq(Set{0, 1})
  end

  it "does not crash when moving on an empty list" do
    list = Tui::List.new([] of Tui::List::Item)
    list.move(1)
    list.cursor.should eq(0)
  end

  it "clears the previous frame before redrawing" do
    list = Tui::List.new([Tui::List::Item.new("a"), Tui::List::Item.new("b")])
    io = IO::Memory.new
    list.render(io, 10)
    io.clear
    list.move(1)
    list.render(io, 10)
    # 4 drawn lines (header + 2 items + footer), cleared upwards from below.
    output = io.to_s
    output.should start_with("\e[1A\e[2K\r" * 4)
  end

  it "truncates long items so they never wrap" do
    list = Tui::List.new([Tui::List::Item.new("a" * 200)])
    io = IO::Memory.new
    list.render(io, 10)
    item_line = io.to_s.split('\n').find { |l| l.includes?("[ ]") }.not_nil!
    item_line.size.should be < 200
    item_line.should contain("…")
  end

  it "repaints only the affected rows on cursor movement" do
    list = Tui::List.new([Tui::List::Item.new("a"), Tui::List::Item.new("b"), Tui::List::Item.new("c")])
    io = IO::Memory.new
    list.render(io, 10)
    io.clear
    list.move(1)
    list.repaint(io, 10, {0, 1})
    output = io.to_s
    # No full-frame clear-and-redraw; just the affected rows rewritten
    # (frame rows: header at 0, items at 1..N, footer at N+1) and the footer.
    output.should_not contain("\e[1A\e[2K\r" * 5)
    output.should contain("\e[4A\e[2K\r")
    output.should contain("\e[3A\e[2K\r")
    output.should contain("\e[1A\e[2K\r") # footer row
  end

  it "renders on the alternate screen and restores it on exit" do
    input = Tui::Input.new(IO::Memory.new("\r"))
    io = IO::Memory.new
    Tui::List.select([Tui::List::Item.new("x")], input, io)
    output = io.to_s
    output.should start_with("\e[?1049h")
    output.should end_with("\e[?1049l")
  end

  it "truncates by visible columns, keeping ANSI sequences intact" do
    list = Tui::List.new([Tui::List::Item.new("\e[31m" + "a" * 200 + "\e[0m")])
    io = IO::Memory.new
    list.render(io, 10)
    line = io.to_s.split("\r\n").find { |l| l.includes?("[ ]") }.not_nil!
    line.should contain("\e[31m")
    visible = line.gsub(/\e\[[0-9;]*m/, "")
    visible.size.should be < 200
    visible.should contain("…")
  end

  it "stops the selection loop at end of input" do
    input = Tui::Input.new(IO::Memory.new(""))
    selected = Tui::List.select([Tui::List::Item.new("x")], input, IO::Memory.new)
    selected.should be_empty
  end

  it "returns an empty selection when cancelled" do
    input = Tui::Input.new(IO::Memory.new("\e"))
    selected = Tui::List.select([Tui::List::Item.new("x")], input, IO::Memory.new)
    selected.should be_empty
  end
end
