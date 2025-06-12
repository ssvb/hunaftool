#!/usr/bin/env ruby
# Copyright © 2025 Siarhei Siamashka
# SPDX-License-Identifier: CC-BY-SA-3.0+ OR MIT

suff_flags = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz"
pref_flags = "0123456789"
comb_flags = "!\"#$%&'()*+,-./:;<=>?@[\\]^_`{|}~"

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

rulesets = [[[""]]].clear

File.open(ARGV[0]).each_line do |l|
  a = l.strip.split
  next unless a[0] == "SFX"

  next if a[2] == "0" || a[2] == "0"

  a = [a[2], a[3], a[0]]

  done = false
  rulesets.each {|ruleset|
    if try_add_rule(ruleset, a)
      done = true
      break
    end
  }

  unless done
    rulesets.push([a]) if rulesets.size < suff_flags.size
  end
end

puts "SET UTF-8"
puts

rulesets.each_with_index do |ruleset, idx|
  code = suff_flags[idx]
  puts "#{ruleset[0][2]} #{code} Y #{ruleset.size}"
  ruleset.each do |rule|
    puts "#{rule[2]} #{code} #{rule[0]} #{rule[1]} ."
  end
  puts
end
