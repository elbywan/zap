module Tui
  # Minimal ANSI escape sequences (in-house replacement for the term-cursor
  # shard). Only what the list renderer needs.
  module Ansi
    # Clear the current line and return the cursor to the first column.
    CLEAR_LINE = "\e[2K\r"

    # Move the cursor up *n* lines.
    def self.move_up(n : Int32) : String
      "\e[#{n}A"
    end

    # Move the cursor down *n* lines.
    def self.move_down(n : Int32) : String
      "\e[#{n}B"
    end

    # Clear *n* lines above the cursor. The cursor sits on the line below the
    # content, so each step moves up then clears: after *n* repetitions the
    # cleared area is gone and the cursor is at the top of it, ready to
    # redraw.
    def self.clear_lines_up(n : Int32) : String
      "\e[1A\e[2K\r" * n
    end

    HIDE_CURSOR = "\e[?25l"
    SHOW_CURSOR = "\e[?25h"

    # Alternate screen buffer: the list renders on a separate screen, and
    # leaving it restores whatever was on the terminal before, untouched.
    ENTER_ALT_SCREEN = "\e[?1049h"
    LEAVE_ALT_SCREEN = "\e[?1049l"

    # Clear the screen and move the cursor to the top-left.
    CLEAR_SCREEN = "\e[2J\e[H"

    RESET  = "\e[0m"
    BOLD   = "\e[1m"
    DIM    = "\e[2m"
    ITALIC = "\e[3m"

    RED    = "\e[31m"
    GREEN  = "\e[32m"
    YELLOW = "\e[33m"
  end
end
