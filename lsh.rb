#!/usr/bin/env ruby
# lsh.rb - single-file Ruby shell
# VERSION: lsh-tab-compgen-fix
#
# Supported ~/.lshrc syntax:
#   alias ll='ls -lah'
#   alias gp='git push'
#   start = 'neofetch'
#
# Controls:
#   Up/Down arrows = history
#   Tab            = bash-like autocomplete
#   Ctrl-C         = exit cleanly
#   Ctrl-D         = exit cleanly

require "io/console"
require "shellwords"
require "etc"

VERSION = "lsh-tab-file-completion-fix"

HISTORY_FILE = File.expand_path("~/.lsh_history")
RC_FILE      = File.expand_path("~/.lshrc")

DEFAULT_LSHRC = <<~RC
# ~/.lshrc
# Uncomment aliases you want to use.

# alias ll='ls -lah'
# alias gs='git status'
# alias gc='git commit'
# alias gp='git push'
# alias gl='git pull'
# alias cls='clear'

# start = 'neofetch'
RC

BUILTINS = %w[
  cd pwd history alias unalias export source reload clear exit quit help rcdebug version testcomplete
].freeze

def strip_outer_quotes(value)
  value = value.to_s.strip
  if (value.start_with?("'") && value.end_with?("'")) ||
     (value.start_with?('"') && value.end_with?('"'))
    value[1...-1]
  else
    value
  end
end

class LineEditor
  MAX_SHOW_WITHOUT_ASK = 20

  def initialize(history, completer)
    @history = history
    @completer = completer
    @last_tab_key = nil
  end

  def read(prompt)
    @prompt = prompt
    @buf = +""
    @pos = 0
    @hist_pos = @history.length
    @saved = +""
    @last_tab_key = nil

    print @prompt
    STDOUT.flush

    STDIN.raw do |stdin|
      @stdin = stdin

      loop do
        ch = stdin.getch

        case ch
        when "\u0003"
          raw_newline
          exit 130
        when "\u0004"
          if @buf.empty?
            raw_newline
            return nil
          end
        when "\r", "\n"
          raw_newline
          return @buf
        when "\u007f", "\b"
          @last_tab_key = nil
          backspace
        when "\t"
          complete
        when "\e"
          @last_tab_key = nil
          escape(stdin)
        else
          @last_tab_key = nil
          insert(ch) if printable?(ch)
        end
      end
    end
  end

  private

  def raw_newline
    print "\r\n"
    STDOUT.flush
  end

  def printable?(ch)
    ch && ch.bytes.all? { |b| b >= 32 && b != 127 }
  end

  def insert(ch)
    @buf.insert(@pos, ch)
    @pos += ch.length
    redraw
  end

  def backspace
    return if @pos <= 0
    @buf.slice!(@pos - 1)
    @pos -= 1
    redraw
  end

  def escape(stdin)
    a = stdin.getch
    return unless a == "["
    b = stdin.getch

    case b
    when "A" then history_up
    when "B" then history_down
    when "C" then move_right
    when "D" then move_left
    when "3"
      stdin.getch
      delete_forward
    end
  rescue
  end

  def history_up
    return if @history.empty?
    @saved = @buf.dup if @hist_pos == @history.length
    @hist_pos -= 1 if @hist_pos > 0
    @buf = @history[@hist_pos].dup
    @pos = @buf.length
    redraw
  end

  def history_down
    return if @history.empty? || @hist_pos >= @history.length
    @hist_pos += 1
    @buf = @hist_pos == @history.length ? @saved.dup : @history[@hist_pos].dup
    @pos = @buf.length
    redraw
  end

  def move_left
    return if @pos <= 0
    @pos -= 1
    print "\e[D"
    STDOUT.flush
  end

  def move_right
    return if @pos >= @buf.length
    @pos += 1
    print "\e[C"
    STDOUT.flush
  end

  def delete_forward
    return if @pos >= @buf.length
    @buf.slice!(@pos)
    redraw
  end

  def complete
    word_start = current_word_start
    word = @buf[word_start...@pos] || ""
    key = [@buf, @pos, word]

    matches = @completer.call(@buf, @pos, word).compact.uniq.sort
    return if matches.empty?

    if matches.length == 1
      replace_word(word_start, matches.first + completion_suffix(matches.first))
      @last_tab_key = nil
      return
    end

    prefix = common_prefix(matches)
    if prefix.length > word.length
      replace_word(word_start, prefix)
      @last_tab_key = nil
      return
    end

    if @last_tab_key != key
      @last_tab_key = key
      print "\a"
      STDOUT.flush
      return
    end

    @last_tab_key = nil
    show_matches_with_prompt(matches)
    redraw
  end

  def completion_suffix(text)
    text.end_with?("/") ? "" : " "
  end

  def show_matches_with_prompt(matches)
    raw_newline

    if matches.length > MAX_SHOW_WITHOUT_ASK
      print "Display all #{matches.length} possibilities? (y or n) "
      STDOUT.flush
      answer = @stdin.getch rescue "n"
      raw_newline
      return unless answer&.downcase == "y"
    end

    print_columns(matches)
  end

  def current_word_start
    left = @buf[0...@pos]
    idx = [left.rindex(" "), left.rindex("\t")].compact.max
    idx ? idx + 1 : 0
  end

  def replace_word(start, text)
    @buf[start...@pos] = text
    @pos = start + text.length
    redraw
  end

  def common_prefix(items)
    prefix = items.first.dup
    items[1..].each do |item|
      prefix = prefix[0...-1] until item.start_with?(prefix) || prefix.empty?
    end
    prefix
  end

  def print_columns(items)
    width = IO.console&.winsize&.[](1) || 80
    max = items.map(&:length).max || 1
    col_width = [max + 2, 1].max
    cols = [width / col_width, 1].max
    rows = (items.length.to_f / cols).ceil

    rows.times do |row|
      line = +""
      cols.times do |col|
        index = row + col * rows
        next unless items[index]
        line << (col == cols - 1 ? items[index] : items[index].ljust(col_width))
      end
      print line
      raw_newline
    end
  end

  def redraw
    print "\r\e[2K"
    print @prompt
    print @buf
    back = @buf.length - @pos
    print "\e[#{back}D" if back > 0
    STDOUT.flush
  end
end

class LSH
  def initialize
    @aliases = {}
    @startup = []
    @exports = {}
    @ignored = []
    @history = []

    first_run_setup
    load_history
    load_rc
    run_startup

    @line = LineEditor.new(@history, method(:complete))
  end

  def run
    loop do
      line = @line.read(prompt)
      break if line.nil?

      line = line.strip
      next if line.empty?

      add_history(line)
      execute(line)
      STDOUT.flush
    end
  rescue SystemExit
    raise
  rescue => e
    warn "lsh: #{e.class}: #{e.message}"
  end

  private

  def first_run_setup
    File.write(HISTORY_FILE, "") unless File.exist?(HISTORY_FILE)
    File.write(RC_FILE, DEFAULT_LSHRC) unless File.exist?(RC_FILE)
  end

  def load_history
    @history = File.readlines(HISTORY_FILE, chomp: true).reject(&:empty?) if File.exist?(HISTORY_FILE)
  rescue
    @history = []
  end

  def add_history(line)
    @history << line
    File.open(HISTORY_FILE, "a") { |f| f.puts(line) }
  rescue => e
    warn "lsh: history error: #{e.message}"
  end

  def load_rc(path = RC_FILE)
    @aliases.clear
    @startup.clear
    @exports.clear
    @ignored.clear

    return unless File.exist?(path)

    File.readlines(path, chomp: true).each_with_index do |raw, index|
      line = raw.delete_suffix("\r").strip
      next if line.empty? || line.start_with?("#")

      if parse_alias(line)
        next
      elsif parse_export(line)
        next
      elsif parse_start(line)
        next
      else
        @ignored << [index + 1, line]
      end
    end
  rescue => e
    warn "lsh: rc error: #{e.message}"
  end

  def parse_alias(line)
    match = line.match(/\Aalias\s+([A-Za-z_][A-Za-z0-9_-]*)\s*=\s*(.+)\z/)
    return false unless match
    @aliases[match[1]] = strip_outer_quotes(match[2])
    true
  end

  def parse_export(line)
    match = line.match(/\Aexport\s+([A-Za-z_][A-Za-z0-9_]*)\s*=\s*(.+)\z/)
    return false unless match

    key = match[1]
    value = strip_outer_quotes(match[2])
    ENV[key] = value
    @exports[key] = value
    true
  end

  def parse_start(line)
    match = line.match(/\Astart\s*=\s*(.+)\z/)
    return false unless match
    command = strip_outer_quotes(match[1])
    @startup << command unless command.empty?
    true
  end

  def run_startup
    @startup.each do |command|
      ok = run_external(command)
      warn "lsh: start failed: #{command}" unless ok
    end
  end

  def bash_path
    ENV.fetch("PATH", "").split(File::PATH_SEPARATOR).each do |dir|
      path = File.join(dir, "bash")
      return path if File.executable?(path)
    end
    nil
  end

  def run_external(command)
    if (bash = bash_path)
      system(bash, "-c", command)
    else
      system(command)
    end
  end

  def prompt
    user = ENV["USER"] || Etc.getlogin || "user"
    host = begin
      `hostname`.strip
    rescue
      "host"
    end

    cwd = Dir.pwd
    home = File.expand_path("~")
    shown =
      if cwd == home
        "~"
      elsif cwd.start_with?(home + File::SEPARATOR)
        cwd.sub(home, "~")
      else
        cwd
      end

    "\e[1;34m#{user}@#{host}\e[0m:\e[1;34m#{shown}\e[0m$ "
  end

  def execute(line)
    expanded = expand_alias(line)
    return if builtin(expanded)
    run_external(expanded)
  rescue Interrupt
    puts
    exit 130
  rescue => e
    warn "lsh: #{e.message}"
  end

  def expand_alias(line)
    first, rest = line.split(/\s+/, 2)
    @aliases.key?(first) ? [@aliases[first], rest].compact.join(" ") : line
  end

  def builtin(line)
    args = Shellwords.split(line)
    return true if args.empty?

    case args[0]
    when "cd"
      Dir.chdir(File.expand_path(args[1] || ENV["HOME"] || Dir.home))
    when "pwd"
      puts Dir.pwd
    when "history"
      @history.each_with_index { |h, i| puts "#{i + 1}  #{h}" }
    when "alias"
      @aliases.sort.each { |name, value| puts "alias #{name}='#{value}'" }
    when "unalias"
      args[1] ? @aliases.delete(args[1]) : warn("lsh: unalias: missing alias name")
    when "export"
      if args.length == 1
        ENV.sort.each { |k, v| puts "export #{k}=#{Shellwords.escape(v)}" }
      else
        warn "lsh: export syntax: export NAME='value'" unless parse_export(line)
      end
    when "source"
      if args[1]
        load_rc(File.expand_path(args[1]))
        run_startup
      else
        warn "lsh: source: missing file"
      end
    when "reload"
      load_rc
      run_startup
    when "rcdebug"
      puts "version: #{VERSION}"
      puts "rc file: #{RC_FILE}"
      puts "rc exists: #{File.exist?(RC_FILE)}"
      puts
      puts "aliases:"
      @aliases.empty? ? puts("  none") : @aliases.sort.each { |name, value| puts "  #{name} = #{value}" }
      puts
      puts "startup:"
      @startup.empty? ? puts("  none") : @startup.each { |command| puts "  #{command}" }
      puts
      puts "ignored rc lines:"
      @ignored.empty? ? puts("  none") : @ignored.each { |line_no, text| puts "  #{line_no}: #{text}" }
    when "testcomplete"
      prefix = args[1] || ""
      complete_command(prefix).each { |x| puts x }
    when "version"
      puts VERSION
    when "clear"
      system("clear")
    when "help"
      puts <<~HELP
        lsh builtins:
          cd [dir]
          pwd
          history
          alias
          unalias name
          export NAME='value'
          source file
          reload
          rcdebug
          version
          testcomplete PREFIX
          clear
          exit

        ~/.lshrc syntax:
          alias ll='ls -lah'
          start = 'neofetch'
      HELP
    when "exit", "quit"
      exit 0
    else
      return false
    end

    true
  rescue => e
    warn "lsh: #{e.message}"
    true
  end

  def complete(buffer, cursor, word)
    before = buffer[0...cursor]
    if before !~ /\s/
      complete_command(word)
    else
      command = before.split(/\s+/).first
      complete_path(word, dirs_only: command == "cd")
    end
  end

  def complete_command(word)
    word ||= ""
    (BUILTINS + @aliases.keys + bash_compgen(word) + path_commands)
      .uniq
      .select { |entry| entry.start_with?(word) }
      .sort
  end

  def bash_compgen(word)
    return [] unless (bash = bash_path)
    escaped = Shellwords.escape(word.to_s)
    out = `#{Shellwords.escape(bash)} -lc 'compgen -c -- #{escaped}' 2>/dev/null`
    out.lines.map(&:chomp).reject(&:empty?)
  rescue
    []
  end

  def path_commands
    ENV.fetch("PATH", "").split(File::PATH_SEPARATOR).flat_map do |dir|
      next [] unless Dir.directory?(dir)
      Dir.each_child(dir).filter_map do |entry|
        path = File.join(dir, entry)
        entry if File.file?(path) && File.executable?(path)
      end
    rescue
      []
    end
  end

  def complete_path(word, dirs_only:)
    word ||= ""

    # Use bash completion for paths. This is much closer to bash behavior than
    # manually scanning directories.
    matches = bash_compgen_path(word, dirs_only: dirs_only)

    # Fallback Ruby completion if bash/compgen is unavailable.
    matches = ruby_path_matches(word, dirs_only: dirs_only) if matches.empty?

    matches.uniq.sort
  rescue
    []
  end

  def bash_compgen_path(word, dirs_only:)
    return [] unless (bash = bash_path)

    escaped = Shellwords.escape(word.to_s)
    mode = dirs_only ? "-d" : "-f"

    out = `#{Shellwords.escape(bash)} -lc 'compgen #{mode} -- #{escaped}' 2>/dev/null`

    out.lines.map(&:chomp).reject(&:empty?).map do |path|
      if File.directory?(expand_tilde(path))
        path.end_with?("/") ? path : "#{path}/"
      else
        path
      end
    end
  rescue
    []
  end

  def ruby_path_matches(word, dirs_only:)
    expanded = expand_tilde(word)

    dir = expanded.end_with?("/") ? expanded : File.dirname(expanded)
    base = expanded.end_with?("/") ? "" : File.basename(expanded)
    dir = "." if dir.nil? || dir.empty?

    return [] unless Dir.directory?(dir)

    Dir.children(dir).filter_map do |entry|
      next unless entry.start_with?(base)

      path = File.join(dir, entry)
      next if dirs_only && !File.directory?(path)

      out = path

      if word.start_with?("~/")
        out = out.sub(File.expand_path("~"), "~")
      elsif !word.start_with?("/")
        out = out.sub(%r{\A\./}, "")
      end

      out += "/" if File.directory?(path)
      out
    end
  rescue
    []
  end

  def expand_tilde(path)
    return File.expand_path("~") if path == "~"
    return File.join(File.expand_path("~"), path[2..]) if path.start_with?("~/")
    path
  end
end

LSH.new.run
