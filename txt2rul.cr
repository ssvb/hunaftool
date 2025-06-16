#!/usr/bin/env crystal
# Copyright © 2025 Siarhei Siamashka
# SPDX-License-Identifier: CC-BY-SA-3.0+ OR MIT

DESIRED_MIN_STRIP_SIZE = 3
# allow to have a condition field up to this size for zero affixes
KEEP_COND_SIZE         = 1
# the maximum number of affixes for a single stem
MAX_STEM_AFFIXES       = 1000
# the number of rules
RULES_LIMIT            = 1000000

# Yield all possible ways of splitting the word into stem/affix pairs
def affix_variants(word)
  0.upto(word.size) do |affsize|
    yield "#{word[0, word.size - affsize]}/#{word[word.size - affsize, affsize]}"
  end
end

def common_prefix_len(word1, word2)
  ans = 0
  0.upto({word1.size, word2.size}.min - 1) do |i|
    return ans if word1[i] != word2[i]
    ans += 1
  end
  return ans
end

# Run an external GNU coreutils sort process. This can be used to sort really
# gigantic multi-terabyte sets of data via zstd-compressed temporary files.
# None of this gigantic data needs to be lifted into RAM, freeing it for the
# other tasks.
def pipe_through_coreutils_sort(sortargs = ["--field-separator=/", "--key=1,1", "--key=2", "--compress-program=zstd"])
  Process.run("sort", args: sortargs, env: {"LC_ALL" => "C"}, input: :pipe, output: :pipe) do |proc|
    # Adjust pipe configuration knobs to minimize flushing overhead and maximize performance
    proc.input.sync             = false
    proc.input.flush_on_newline = false
    proc.output.read_buffering  = true
    # Yield the prepared input and output pipes
    yield proc.input, proc.output
  end
end

# This yield all possible stripping/affix combinations for a common stem.
def affcombs(stem, affixes)
  if affixes.size > MAX_STEM_AFFIXES
    STDERR.puts "! The stem «#{stem}» has #{affixes.size} affixes and exceeds the allowed limit - SKIPPED."
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

def affixpairs
  pipe_through_coreutils_sort do |sort_input, sort_output|
    File.open(ARGV[0]).each_line do |l|
      affix_variants(l) do |sepaffix|
        sort_input.puts sepaffix
      end
    end
    sort_input.close

    stem = ""
    affixes = [['a']].clear
    sort_output.each_line do |l|
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

def combine_counters
  pipe_through_coreutils_sort do |sort_input, sort_output|
    affixpairs do |affcomb|
      sort_input.puts affcomb
    end
    sort_input.close

    p1 = ""
    p2 = ""
    cnt = 0
    sort_output.each_line do |l|
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

STDOUT.flush_on_newline = false
STDOUT.sync = false
pipe_through_coreutils_sort(["--field-separator=/", "--key=3,3nr", "--key=1,2", "--compress-program=zstd"]) do |sort_input, sort_output|
  combine_counters do |l|
    sort_input.puts l
  end
  sort_input.close

  rules_cnt = 0
  sort_output.each_line do |l|
    a = l.strip.split('/')
    STDOUT.puts "SFX ? #{a[0] == "" ? "0" : a[0]} #{a[1] == "" ? "0" : a[1]} .\t##{a[2]}" if a[2].to_i > 1
    if (rules_cnt += 1) >= RULES_LIMIT
      STDERR.puts "! rules limit exceeded"
      sort_output.close
      break
    end
  end
end
