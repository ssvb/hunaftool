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

File.open(ARGV[0]).each_line {|l|
  a = l.strip.split('/')

  done = false
  rulesets.each {|ruleset|
    if try_add_rule(ruleset, a)
      done = true
      break
    end
  }

  unless done
    rulesets.push([a]) if rulesets.size < 26 * 2
  end
}

puts "SET UTF-8"
puts

rulesets.each_with_index {|ruleset, idx|
  code = ('A'.ord + idx).chr
  if idx >= 26
    code = ('a'.ord + idx - 26).chr
  end
  puts "SFX #{code} Y #{ruleset.size}"
  ruleset.each {|rule|
    puts "SFX #{code} #{rule[0] == "" ? "0" : rule[0]} #{rule[1] == "" ? "0" : rule[1]} ."
  }
  puts
}
