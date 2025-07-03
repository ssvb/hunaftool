#!/usr/bin/env ruby
# Copyright © 2025 Siarhei Siamashka
# SPDX-License-Identifier: CC-BY-SA-3.0+ OR MIT

# This is how runing under Crystal can be detected.
COMPILED_BY_CRYSTAL = (((1 / 2) * 2) != 0)

# This is a Ruby-compatible trick to create a Crystal's lightweight tuple
def tuple2(a, b) return a, b end

# This icky blob of code aliases the Ruby's "respond_to?" method to "responds_to?",
# making it easier to maintain the source level compatibility with Crystal. And
# also provides access to the "eval_if_run_by_ruby" function, which does "eval"
# when the code is run by Ruby, but does nothing when the code is compiled by
# Crystal. It can be used to define additional aliases necessary for Ruby/Crystal
# compatibility.
module Kernel def method_missing(name, *args) true end end
if (k5324534 = Kernel).responds_to? :eval ; k5324534.eval "class Object alias
responds_to? respond_to? end ; module Kernel undef method_missing end" end
def eval_if_run_by_ruby(src) if (k = Kernel).responds_to? :eval ; k.eval src end end

# Change the String's "split" method in Ruby not to omit trailing empty fields
# by default in order to make its default behaviour the same as in Crystal.
eval_if_run_by_ruby "class String alias split_orig42351 split
def split(pattern = nil, limit = -1) block_given? ? split_orig42351(
pattern, limit) {|x| yield x } : split_orig42351(pattern, limit) end end"

DESIRED_MIN_STRIP_SIZE = 3
# allow to have a condition field up to this size for zero affixes
KEEP_COND_SIZE         = 1
# the maximum number of affixes for a single stem
MAX_STEM_AFFIXES       = 1000
# the number of rules
RULES_LIMIT            = 1000000

module Cfg
  @@prefix_mode = false
  def self.prefix_mode?   ; @@prefix_mode end
  def self.prefix_mode=(v) ; @@prefix_mode = v end
end

args = ARGV.select do |arg|
  if arg =~ /^\-p$/
    Cfg.prefix_mode = true
    nil
  elsif arg =~ /^\-/
    abort "Unrecognized command line option: '#{arg}'\n"
  else
    arg
  end
end

unless args.size >= 1
  abort "Need file name in the command line (with the list of words)"
end

# Yield all possible ways of splitting the word into stem/affix pairs
def affix_variants(word)
  0.upto(word.size) do |affsize|
    yield "#{word[0, word.size - affsize]}/#{word[word.size - affsize, affsize]}"
  end
end

def common_prefix_len(word1, word2)
  ans = 0
  0.upto(tuple2(word1.size, word2.size).min - 1) do |i|
    return ans if word1[i] != word2[i]
    ans += 1
  end
  return ans
end

# Run an external GNU coreutils sort process. This can be used to sort really
# gigantic multi-terabyte sets of data via zstd-compressed temporary files.
# None of this gigantic data needs to be lifted into RAM, freeing it for the
# other tasks.

class EmulatedIoPopenPipe
  @pipe_input, @pipe_output = STDOUT, STDIN
  def initialize(pipe_input, pipe_output)
    @pipe_input, @pipe_output = pipe_input, pipe_output
  end
  def close_write ; @pipe_input.close   end
  def close       ; @pipe_output.close  end
  def puts(s)     ; @pipe_input.puts(s) end
  def gets        ; @pipe_output.gets   end
  def each_line   ; @pipe_output.each_line {|line| yield line } end
end

def pipe_through_coreutils_sort(sortargs = ["--field-separator=/", "--key=1,1", "--key=2", "--compress-program=zstd"])
  if COMPILED_BY_CRYSTAL
    Process.run("sort", args: sortargs, env: {"LC_ALL" => "C"}, input: :pipe, output: :pipe) do |proc|
      # Adjust pipe configuration knobs to minimize flushing overhead and maximize performance
      proc.input.sync             = false
      proc.input.flush_on_newline = false
      proc.output.read_buffering  = true
      # Yield the prepared input and output pipes
      yield EmulatedIoPopenPipe.new(proc.input, proc.output)
    end
  elsif (io = IO).responds_to?(:popen)
    io.popen({"LC_ALL" => "C"}, ["sort"] + sortargs, "r+") do |pipe|
      pipe.sync = false
      yield pipe
    end
  else
    raise "should be unreachable\n"
  end
end

# This yield all possible stripping/affix combinations for a common stem.
def affcombs(stem, affixes)
  if affixes.size > MAX_STEM_AFFIXES
    if Cfg.prefix_mode?
      STDERR.puts "! The stem «#{stem.reverse}» has #{affixes.size} prefixes and this exceeds the allowed limit - SKIPPED."
    else
      STDERR.puts "! The stem «#{stem}» has #{affixes.size} suffixes and this exceeds the allowed limit - SKIPPED."
    end
    return
  end

    0.upto(affixes.size - 1) do |i|
      (i + 1).upto(affixes.size - 1) do |j|
        len = common_prefix_len(affixes[i], affixes[j])
        if len == 0 || ((affixes[i].size - len) < DESIRED_MIN_STRIP_SIZE && len <= KEEP_COND_SIZE)
          yield "#{affixes[i].join}/#{affixes[j].join}/1"
        end
        if len == 0 || ((affixes[j].size - len) < DESIRED_MIN_STRIP_SIZE && len <= KEEP_COND_SIZE)
          yield "#{affixes[j].join}/#{affixes[i].join}/1"
        end
      end
    end
end

def affixpairs(args)
  pipe_through_coreutils_sort do |pipe|
    File.open(args[0]).each_line do |l|
      l = l.strip
      if Cfg.prefix_mode?
        l = l.reverse
      end
      affix_variants(l) do |sepaffix|
        pipe.puts sepaffix
      end
    end
    pipe.close_write

    stem = ""
    affixes = [['a']].clear
    pipe.each_line do |l|
      a = l.strip.split('/')
      if a[0] != stem
        affcombs(stem, affixes) {|affcomb| yield affcomb }
        stem = a[0]
        affixes.clear
      end
      affixes.push(a[1].chars)
    end
    affcombs(stem, affixes) {|affcomb| yield affcomb }
  end
end

def combine_counters(args)
  pipe_through_coreutils_sort do |pipe|
    affixpairs(args) do |affcomb|
      pipe.puts affcomb
    end
    pipe.close_write

    p1 = ""
    p2 = ""
    cnt = 0
    pipe.each_line do |l|
      a = l.strip.split('/')
      if a[0] == p1 && a[1] == p2
        cnt += a[2].to_i
      else
        yield "#{p1}/#{p2}/#{cnt}" if cnt > 0
        p1 = a[0]
        p2 = a[1]
        cnt = a[2].to_i
      end
    end
    yield "#{p1}/#{p2}/#{cnt}" if cnt > 0
  end
end

STDOUT.flush_on_newline = false if COMPILED_BY_CRYSTAL
STDOUT.sync = false

pipe_through_coreutils_sort(["--field-separator=/",
                             "--key=3,3nr", "--key=1,2",
                             "--compress-program=zstd"]) do |pipe|
  combine_counters(args) {|line| pipe.puts line }
  pipe.close_write

  rules_cnt = 0
  out_data = [[""]].clear
  out_col_width = [0, 0, 0]
  pipe.each_line do |l|
    a = l.strip.split('/')
    if Cfg.prefix_mode?
      a[0] = a[0].reverse
      a[1] = a[1].reverse
    end
    if a[2].to_i > 1
      out_data.push([a[0] == "" ? "0" : a[0], a[1] == "" ? "0" : a[1], "hunaftool:freq=#{a[2]}"])
      out_col_width.each_index {|i| out_col_width[i] = out_data.last[i].size if out_data.last[i].size > out_col_width[i] }
      break if (rules_cnt += 1) >= RULES_LIMIT
    end
  end
  pipe.close
  out_data.each do |row|
    printf("#%s  %#{out_col_width[0]}s %-#{out_col_width[1]}s  %s\n", (Cfg.prefix_mode? ? "prefix" : "suffix"), row[0], row[1], row[2])
  end
end

STDOUT.flush
