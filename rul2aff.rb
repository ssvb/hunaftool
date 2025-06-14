#!/usr/bin/env ruby
# Copyright © 2025 Siarhei Siamashka
# SPDX-License-Identifier: CC-BY-SA-3.0+ OR MIT

suff_flags = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz"
pref_flags = "0123456789"
comb_flags = "!\"#$%&'()*+,-./:;<=>?@[\\]^_`{|}~"

suff_flags += pref_flags
#suff_flags += comb_flags

suff_flags = suff_flags.chars.sort.uniq.join

def independent?(a, b)
  a, b = b, a if b[0].size > a[0].size
  return a[0][-b[0].size, b[0].size] != b[0]
end

def try_add_rule(rules, rule)
  bad = false
  rules.each {|oldrule|
    unless independent?(oldrule, rule)
      bad = true
      break
    end
  }
  unless bad
    rules << rule
    return true
  end
  return false
end

def tuple2(x, y)
  return x, y
end
aff_to_rule_id = {tuple2(0, "") => 0}.clear

rulesets = [[[""]]].clear

log_rejected = nil
if ARGV.size >= 2
  log_rejected = File.open(ARGV[1], "w")
end

linenum = 0
lastline = 0
File.open(ARGV[0]).each_line do |l|
  linenum += 1
  a = l.strip.split
  next unless a[0] == "SFX"
  next if a[2] == "0" || a[3] == "0" || a[2].size < 2
  a = [a[2], a[3], a[0]]

  # matching affix
  if (id = aff_to_rule_id.fetch(tuple2(a[0].size, a[1]), nil))
    rulesets[id].push(a)
    next
  end

  done = false
  rulesets.each_with_index {|ruleset, id|
    if try_add_rule(ruleset, a)
      aff_to_rule_id[tuple2(a[0].size, a[1])] = id
      done = true
      break
    end
  }

  lastline = linenum if done

  unless done
    if rulesets.size < suff_flags.size
      aff_to_rule_id[tuple2(a[0].size, a[1])] = rulesets.size
      rulesets.push([a])
      lastline = linenum
    else
      if log_rejected
        log_rejected.puts l.strip
      end
    end
  end
end

puts "# used arul entries up to line #{lastline}"
puts "SET UTF-8"
puts "WORDCHARS -ʼ’'"
puts

rulesets.each_with_index do |ruleset, idx|
  code = suff_flags[idx]
  puts "#{ruleset[0][2]} #{code} Y #{ruleset.size}"
  ruleset.each do |rule|
    puts "#{rule[2]} #{code} #{rule[0]} #{rule[1]} ."
  end
  puts
end
