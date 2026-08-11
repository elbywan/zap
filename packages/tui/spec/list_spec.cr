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
  it "fuzzy matches by subsequence, case-insensitively" do
    Tui::List.fuzzy_match?("tlr", "@testing-library/react").should be_true
    Tui::List.fuzzy_match?("TLR", "@testing-library/react").should be_true
    Tui::List.fuzzy_match?("xyz", "@testing-library/react").should be_false
    Tui::List.fuzzy_match?("", "anything").should be_true
  end

  it "cycles the tag filter and narrows the visible subset" do
    list = Tui::List.new([
      Tui::List::Item.new("a", tag: "major"),
      Tui::List::Item.new("b", tag: "minor"),
      Tui::List::Item.new("c", tag: "major"),
    ])
    list.visible_indices.should eq([0, 1, 2])
    list.cycle_filter
    list.visible_indices.should eq([0, 2])
    list.cycle_filter
    list.visible_indices.should eq([1])
    list.cycle_filter
    list.visible_indices.should eq([0, 1, 2])
  end

  it "narrows the visible subset with the search text" do
    list = Tui::List.new([
      Tui::List::Item.new("react"),
      Tui::List::Item.new("react-dom"),
      Tui::List::Item.new("lodash"),
    ])
    list.search = "rdom"
    list.visible_indices.should eq([1])
  end

  it "maps toggles through the visible subset to full item indices" do
    list = Tui::List.new([
      Tui::List::Item.new("a", tag: "major"),
      Tui::List::Item.new("b", tag: "minor"),
      Tui::List::Item.new("c", tag: "major"),
    ])
    list.cycle_filter # major only
    list.toggle       # item 0
    list.selected.should eq(Set{0})
    list.move(1)      # to item 2 (the second major)
    list.toggle
    list.selected.should eq(Set{0, 2})
  end

  it "selects or clears only the visible items with toggle_all" do
    list = Tui::List.new([
      Tui::List::Item.new("a", tag: "major"),
      Tui::List::Item.new("b", tag: "minor"),
      Tui::List::Item.new("c", tag: "major"),
    ])
    list.cycle_filter # major only
    list.toggle_all
    list.selected.should eq(Set{0, 2})
    list.toggle_all
    list.selected.should be_empty
  end

  it "keeps the caret marker on the focused item while scrolling" do
    items = (0...20).map { |i| Tui::List::Item.new("pkg#{i}") }
    list = Tui::List.new(items)
    list.move(15) # scrolls the window to pkg10..pkg19, caret on pkg15
    io = IO::Memory.new
    list.render(io, 10)
    lines = io.to_s.split("\r\n").select { |l| l.includes?("[ ]") }
    lines.size.should eq(10)
    lines[5].should start_with("> [ ] pkg15")
    lines.each_with_index do |line, i|
      (i == 5).should eq(line.starts_with?("> "))
    end
  end

  it "repaints scrolled caret rows at their frame positions" do
    items = (0...20).map { |i| Tui::List::Item.new("pkg#{i}") }
    list = Tui::List.new(items)
    list.move(16) # first = 10, caret at window position 6 (frame row 7)
    io = IO::Memory.new
    list.render(io, 10)
    io.clear
    list.move(17)
    list.repaint(io, 10, {16, 17})
    output = io.to_s
    # drawn_lines = 12: old caret row 7, new caret row 8, footer row 11.
    output.should contain("\e[5A\e[2K\r")
    output.should contain("\e[4A\e[2K\r")
    output.should contain("\e[1A\e[2K\r")
  end

  it "exits search mode with backspace on an empty query" do
    # Search, backspace on the empty query, then space: with the search
    # exited the space toggles the item instead of extending the query.
    input = Tui::Input.new(IO::Memory.new("/\x7f "))
    selected = Tui::List.select([Tui::List::Item.new("x")], input, IO::Memory.new)
    selected.should eq(Set{0})
  end

  it "restores the caret to the pre-search item when clearing the search" do
    items = (0...10).map { |i| Tui::List::Item.new("pkg#{i}") }
    list = Tui::List.new(items)
    list.move(5)
    list.start_search
    list.cursor.should eq(0)
    list.clear_search
    list.cursor.should eq(5)
  end

  it "repaints the previous caret row when moving during a search" do
    input = Tui::Input.new(IO::Memory.new("/jest\x1b[B"))
    io = IO::Memory.new
    Tui::List.select([
      Tui::List::Item.new("jest-a"),
      Tui::List::Item.new("jest-b"),
      Tui::List::Item.new("jest-c"),
    ], input, io)
    last = io.to_s.split("\e[?25l").last
    # The down repaint must rewrite both the old caret row (5) and the new
    # one (4); otherwise the old marker lingers and two carets are shown.
    last.should contain("\e[5A\e[2K\r")
    last.should contain("\e[4A\e[2K\r")
  end

  it "toggles the item under the caret while searching" do
    input = Tui::Input.new(IO::Memory.new("/jest "))
    selected = Tui::List.select([
      Tui::List::Item.new("jest-a"),
      Tui::List::Item.new("jest-b"),
      Tui::List::Item.new("jest-c"),
    ], input, IO::Memory.new)
    selected.should eq(Set{0})
  end

  it "truncates a long search query so it never wraps" do
    input = Tui::Input.new(IO::Memory.new("/" + "a" * 300))
    io = IO::Memory.new
    Tui::List.select([Tui::List::Item.new("x")], input, io)
    frames = io.to_s.split("\e[?25l")
    last = frames.last.gsub(/\e\[[0-9;]*m/, "")
    line = last.split("\r\n").find { |l| l.starts_with?("  /aaa") }.not_nil!
    line.should contain("…")
    line.size.should be < 100
  end

end
