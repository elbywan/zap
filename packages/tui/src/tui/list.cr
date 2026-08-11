module Tui
  # `struct winsize` and the ioctl syscall (TIOCGWINSZ), not bound by the
  # stdlib; used to query the real terminal size.
  struct Winsize
    getter ws_row : UInt16 = 0_u16
    getter ws_col : UInt16 = 0_u16
    getter ws_xpixel : UInt16 = 0_u16
    getter ws_ypixel : UInt16 = 0_u16
  end

  lib LibTui
    fun ioctl(fd : Int32, request : UInt64, arg : Void*) : Int32
  end

  # A scrollable multi-select list. The model (items, cursor, selection) is
  # pure logic; rendering writes ANSI sequences through `Ansi`.
  class List
    record Item,
      label : String,
      sublabel : String? = nil,
      # ANSI style prefix applied to the sublabel (e.g. italic+dim). The label
      # embeds its own styles.
      sublabel_style : String = ""

    # Height of the visible window, in item rows (excluding header/footer).
    WINDOW_HEIGHT = 10

    # Terminal width in columns, reported by the kernel when available
    # (COLUMNS is not always kept in sync by shells). Items are truncated to
    # it so they never wrap: a wrapped line would corrupt the frame
    # bookkeeping.
    private def self.terminal_columns : Int32
      winsize = Winsize.new
      if LibTui.ioctl(0, 0x5413_u64, pointerof(winsize).as(Void*)) == 0 && winsize.ws_col > 0
        winsize.ws_col.to_i32
      else
        ENV["COLUMNS"]?.try(&.to_i?) || 80
      end
    rescue
      ENV["COLUMNS"]?.try(&.to_i?) || 80
    end

    COLUMNS = terminal_columns.clamp(20, 500)

    getter items : Array(Item)
    getter cursor : Int32 = 0
    getter selected : Set(Int32) = Set(Int32).new

    def initialize(@items : Array(Item))
    end

    def move(delta : Int32) : Nil
      return if @items.empty?
      @cursor = (@cursor + delta).clamp(0, @items.size - 1)
    end

    # Toggles the item under the cursor.
    def toggle : Nil
      if @selected.includes?(@cursor)
        @selected.delete(@cursor)
      else
        @selected << @cursor
      end
    end

    # Selects all items when some are unselected, otherwise clears the
    # selection (the `a` key).
    def toggle_all : Nil
      if @selected.size == @items.size
        @selected.clear
      else
        @items.each_index { |i| @selected << i }
      end
    end

    # Runs the selection loop and returns the selected indices (empty when the
    # user cancels with escape or ctrl-c). The terminal must already be in raw
    # mode. The first frame is drawn in full; cursor moves and toggles only
    # repaint the affected rows.
    def self.select(
      items : Array(Item),
      input : Input,
      io : IO = STDOUT,
      window_height : Int32 = WINDOW_HEIGHT,
    ) : Set(Int32)
      list = new(items)
      # Render on the alternate screen so the caller's output is restored,
      # untouched, when the selection loop exits.
      io << Ansi::ENTER_ALT_SCREEN << Ansi::CLEAR_SCREEN
      begin
        list.render(io, window_height)
        loop do
          key, byte = input.next_key
          case key
          in Key::Up
            previous = list.cursor
            list.move(-1)
            list.repaint(io, window_height, {previous, list.cursor})
          in Key::Down
            previous = list.cursor
            list.move(1)
            list.repaint(io, window_height, {previous, list.cursor})
          in Key::Space
            list.toggle
            list.repaint(io, window_height, {list.cursor})
          in Key::Enter
            break
          in Key::Escape, Key::CtrlC
            return Set(Int32).new
          in Key::Other
            break if byte == -1 # end of input: stop redrawing
            if byte == 0x61 # 'a'
              list.toggle_all
              list.render(io, window_height)
            end
          in Key::Left, Key::Right
            # Not used by the list.
          end
        end
        list.selected
      ensure
        io << Ansi::LEAVE_ALT_SCREEN
        io.flush
      end
    end

    # Renders the visible window, redrawing over whatever was drawn before.
    def render(io : IO, window_height : Int32 = WINDOW_HEIGHT) : Nil
      # The cursor sits below the previously drawn area; clear it upwards so
      # the old content cannot bleed into the new frame.
      io << Ansi.clear_lines_up(@drawn_lines) if @drawn_lines > 0
      io << Ansi::HIDE_CURSOR
      io << header
      @visible_window = visible_items(window_height)
      @visible_window.each do |index|
        io << item_line(index)
      end
      io << footer
      io << Ansi::SHOW_CURSOR
      @drawn_lines = 2 + @visible_window.size
      io.flush
    end

    # Repaints the given item indices in place; falls back to a full redraw
    # when the visible window scrolled.
    def repaint(io : IO, window_height : Int32, indices : Enumerable(Int32)) : Nil
      window = visible_items(window_height)
      unless window == @visible_window
        render(io, window_height)
        return
      end
      indices.each do |index|
        if position = window.index(index)
          # Frame rows: header at 0, items at 1..N, footer at N+1.
          draw_row(io, position + 1)
        end
      end
      # The footer carries the selection count, which toggles change.
      draw_row(io, @visible_window.size + 1)
      io.flush
    end

    # Removes the frame from the terminal, leaving the cursor below it.
    def clear(io : IO) : Nil
      return if @drawn_lines == 0
      io << Ansi.clear_lines_up(@drawn_lines)
      @drawn_lines = 0
      io.flush
    end

    # -- private --

    @drawn_lines = 0
    @visible_window = [] of Int32

    private def header : String
      visible = "Select packages to update  (up/down move, space select, a all/none, enter upgrade, esc cancel)"
      # CRLF: in raw mode the output newline translation is off, so a bare \n
      # moves down without returning to column 0.
      "  #{Ansi::BOLD}#{truncate(visible, COLUMNS - 3)}#{Ansi::RESET}\r\n"
    end

    private def footer : String
      "#{Ansi::DIM}#{@selected.size} of #{@items.size} selected#{Ansi::RESET}\r\n"
    end

    private def visible_items(window_height : Int32) : Array(Int32)
      size = @items.size
      window = Math.min(window_height, size)
      first = (@cursor - window // 2).clamp(0, size - window)
      (first...first + window).to_a
    end

    private def item_line(index : Int32) : String
      item = @items[index]
      marker = @cursor == index ? "> " : "  "
      check = @selected.includes?(index) ? "[x]" : "[ ]"
      prefix = "#{marker}#{check} "
      label = truncate(item.label, COLUMNS - prefix.size - 2)
      if sublabel = item.sublabel
        remaining = COLUMNS - prefix.size - visible_size(label) - 2
        sub = truncate(sublabel, remaining)
        "#{prefix}#{label}  #{item.sublabel_style}#{sub}#{Ansi::RESET}\r\n"
      else
        "#{prefix}#{label}\r\n"
      end
    end

    # Moves the cursor up to the given frame row, rewrites it in place and
    # moves back below the frame.
    private def draw_row(io : IO, row : Int32) : Nil
      io << Ansi.move_up(@drawn_lines - row)
      io << Ansi::CLEAR_LINE
      io << row_content(row)
      # Back to column 0 on the line below the frame: move_down keeps the
      # column, so without this the caret would blink at the end of the last
      # repainted row.
      io << Ansi.move_down(@drawn_lines - row) << "\r"
    end

    private def row_content(row : Int32) : String
      case row
      when 0
        header.chomp("\r\n")
      when @visible_window.size + 1
        footer.chomp("\r\n")
      else
        item_line(@visible_window[row - 1]).chomp("\r\n")
      end
    end

    # Truncates text to *max* visible columns, keeping any ANSI SGR sequences
    # embedded in it intact and closing open styles before the ellipsis.
    private def truncate(text : String, max : Int32) : String
      return text if max <= 0
      visible = 0
      out = String.build do |str|
        text.scan(/\e\[[0-9;]*m|./m) do |match|
          token = match[0]
          if token.starts_with?('\e')
            str << token
          elsif visible < max
            str << token
            visible += 1
          else
            break
          end
        end
      end
      return text if out == text
      "#{out}…#{Ansi::RESET}"
    end

    # The number of visible columns in *text*, ignoring ANSI sequences.
    private def visible_size(text : String) : Int32
      text.gsub(/\e\[[0-9;]*m/, "").size
    end
  end
end
