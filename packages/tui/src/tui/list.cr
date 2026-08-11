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

  # A scrollable multi-select list with a fuzzy search (`/`) and a filter
  # cycle over item tags (`f`). The model is pure logic; rendering writes
  # ANSI sequences through `Ansi`.
  class List
    record Item,
      label : String,
      sublabel : String? = nil,
      # ANSI style prefix applied to the sublabel (e.g. italic+dim). The label
      # embeds its own styles.
      sublabel_style : String = "",
      # Optional tag matched by the filter cycle (e.g. the bump severity).
      tag : String? = nil

    # Fallback window height, in item rows (excluding header/footer), when
    # the terminal size cannot be queried.
    WINDOW_HEIGHT = 10

    private def self.terminal_size : {Int32, Int32}
      winsize = Winsize.new
      if LibTui.ioctl(0, 0x5413_u64, pointerof(winsize).as(Void*)) == 0
        {winsize.ws_row.to_i32, winsize.ws_col.to_i32}
      else
        {0, 0}
      end
    rescue
      {0, 0}
    end

    # Terminal width in columns, reported by the kernel when available
    # (COLUMNS is not always kept in sync by shells). Items are truncated to
    # it so they never wrap: a wrapped line would corrupt the frame
    # bookkeeping.
    COLUMNS = begin
      rows, cols = terminal_size
      cols > 0 ? cols.clamp(20, 500) : (ENV["COLUMNS"]?.try(&.to_i?) || 80).clamp(20, 500)
    end

    # Window height in item rows, derived from the terminal height minus the
    # header, the footer and a margin, so the list adapts to the screen.
    private def self.terminal_height : Int32
      rows, _ = terminal_size
      rows > 0 ? (rows - 4).clamp(3, 40) : WINDOW_HEIGHT
    end

    getter items : Array(Item)
    # Position of the cursor within the currently visible subset.
    property cursor : Int32 = 0
    # Full item indices, independent of the visible subset.
    getter selected : Set(Int32) = Set(Int32).new
    property search : String = ""
    property searching : Bool = false
    getter active_filter : String? = nil
    # Item the caret was on when the search started; the caret returns there
    # when the search is cleared (escape, or backspace on an empty query).
    property search_anchor : Int32? = nil

    def initialize(@items : Array(Item))
    end

    # Enters search mode, remembering the item the caret is on so clearing the
    # search can bring it back.
    def start_search : Nil
      @search_anchor = visible_indices[@cursor]?
      @search = ""
      @cursor = 0
      @searching = true
    end

    # Leaves search mode and restores the caret to the pre-search item.
    def clear_search : Nil
      @searching = false
      @search = ""
      @cursor = if anchor = @search_anchor
                  visible_indices.index(anchor) || 0
                else
                  0
                end
      @search_anchor = nil
    end

    # The item indices currently visible (search and filter applied).
    def visible_indices : Array(Int32)
      @items.each_index.select { |i| visible?(i) }.to_a
    end

    private def visible?(index : Int32) : Bool
      item = @items[index]
      (@search.empty? || self.class.fuzzy_match?(@search, item.label)) &&
        (@active_filter.nil? || item.tag == @active_filter)
    end

    def move(delta : Int32) : Nil
      return if visible_indices.empty?
      @cursor = (@cursor + delta).clamp(0, visible_indices.size - 1)
    end

    # Toggles the item under the cursor.
    def toggle : Nil
      if index = visible_indices[@cursor]?
        if @selected.includes?(index)
          @selected.delete(index)
        else
          @selected << index
        end
      end
    end

    # Selects all visible items when some are unselected, otherwise clears
    # the visible selection (the `a` key).
    def toggle_all : Nil
      visible = visible_indices
      all_selected = visible.all? { |i| @selected.includes?(i) }
      visible.each do |i|
        if all_selected
          @selected.delete(i)
        else
          @selected << i
        end
      end
    end

    # Cycles the tag filter: none -> first tag -> ... -> last tag -> none.
    def cycle_filter : Nil
      tags = @items.compact_map(&.tag).uniq.sort
      return if tags.empty?
      index = @active_filter ? tags.index(@active_filter).not_nil! : -1
      next_index = (index + 1) % (tags.size + 1)
      @active_filter = next_index < tags.size ? tags[next_index] : nil
      @cursor = 0
    end

    # Case-insensitive subsequence match (fuzzy): every query character must
    # appear in order in the text.
    def self.fuzzy_match?(query : String, text : String) : Bool
      return true if query.empty?
      query_chars = query.downcase.chars
      text_chars = text.downcase.chars
      i = 0
      query_chars.each do |c|
        while i < text_chars.size && text_chars[i] != c
          i += 1
        end
        return false if i >= text_chars.size
        i += 1
      end
      true
    end

    # Runs the selection loop and returns the selected indices (empty when the
    # user cancels with escape or ctrl-c). The terminal must already be in raw
    # mode. The first frame is drawn in full; cursor moves and toggles only
    # repaint the affected rows.
    def self.select(
      items : Array(Item),
      input : Input,
      io : IO = STDOUT,
      window_height : Int32 = terminal_height,
    ) : Set(Int32)
      list = new(items)
      # Render on the alternate screen so the caller's output is restored,
      # untouched, when the selection loop exits.
      io << Ansi::ENTER_ALT_SCREEN << Ansi::CLEAR_SCREEN
      begin
        list.render(io, window_height)
        loop do
          key, byte = input.next_key
          break if byte == -1 # end of input: stop redrawing
          if list.searching
            handle_search_key(list, key, byte, io, window_height)
            next
          end
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
            if byte == 0x2f # '/'
              list.start_search
              list.render(io, window_height)
            elsif byte == 0x66 # 'f'
              list.cycle_filter
              list.render(io, window_height)
            elsif byte == 0x61 # 'a'
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

    # Handles a key while the search line is active.
    private def self.handle_search_key(list : List, key : Key, byte : Int32, io : IO, window_height : Int32) : Nil
      case key
      in Key::Enter
        list.searching = false
        list.search_anchor = nil
        list.render(io, window_height)
      in Key::Escape
        list.clear_search
        list.render(io, window_height)
      in Key::Up
        previous = list.cursor
        list.move(-1)
        list.repaint(io, window_height, {previous, list.cursor})
      in Key::Down
        previous = list.cursor
        list.move(1)
        list.repaint(io, window_height, {previous, list.cursor})
      in Key::Other
        if byte == 0x7f # backspace
          if list.search.empty?
            list.clear_search
          else
            list.search = list.search[0...-1]
            list.cursor = 0
          end
          list.render(io, window_height)
        elsif byte >= 0x20 && byte <= 0x7e
          list.search += byte.chr
          list.cursor = 0
          list.render(io, window_height)
        end
      in Key::Space
        # Toggle the item under the caret; a literal space in the query is
        # not worth blocking selection on.
        list.toggle
        list.repaint(io, window_height, {list.cursor})
      in Key::Left, Key::Right, Key::CtrlC
        # Not used while searching.
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
      @visible_window.each_with_index do |index, position|
        io << item_line(index, position)
      end
      io << footer
      if @searching
        query = @search.empty? ? "/" : "/#{@search}"
        io << "  #{Ansi::BOLD}#{truncate(query, COLUMNS - 3)}#{Ansi::RESET}\r\n"
      end
      io << Ansi::SHOW_CURSOR
      @drawn_lines = 2 + @visible_window.size + (@searching ? 1 : 0)
      io.flush
    end

    # Repaints the given cursor positions in place; falls back to a full
    # redraw when the visible window scrolled.
    def repaint(io : IO, window_height : Int32, positions : Enumerable(Int32)) : Nil
      window = visible_items(window_height)
      unless window == @visible_window
        render(io, window_height)
        return
      end
      positions.each do |position|
        row = position - @first + 1
        draw_row(io, row) if row >= 1 && row <= window.size
      end
      # The footer carries the selection count, which toggles change.
      draw_row(io, @visible_window.size + 1)
      io.flush
    end

    # -- private --

    @drawn_lines = 0
    @visible_window = [] of Int32
    @first = 0

    private def header : String
      visible = "Select packages to update  (up/down move, space select, a all/none, / search, f filter, enter upgrade, esc cancel)"
      "  #{Ansi::BOLD}#{truncate(visible, COLUMNS - 3)}#{Ansi::RESET}\r\n"
    end

    private def footer : String
      visible_count = visible_indices.size
      filter = @active_filter ? " (#{@active_filter})" : ""
      "#{Ansi::DIM}#{@selected.size} of #{@items.size} selected#{filter}#{Ansi::RESET}\r\n"
    end

    private def visible_items(window_height : Int32) : Array(Int32)
      visible = visible_indices
      window = Math.min(window_height, visible.size)
      @first = (@cursor - window // 2).clamp(0, visible.size - window)
      visible[@first, window]
    end

    private def item_line(index : Int32, position : Int32) : String
      item = @items[index]
      # The caret row is the cursor's visible-subset position offset by the
      # window start; comparing against the raw cursor would drift off the
      # bottom once the window scrolls.
      marker = position == @cursor - @first ? "> " : "  "
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
        item_line(@visible_window[row - 1], row - 1).chomp("\r\n")
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
