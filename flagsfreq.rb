# Monkey-patch Ruby to make it recognize the Crystal's .to_i128 method
class Integer def to_i128() to_i end end
# A 128-bit zero constant to hint the use of Int128 instead of Int32 for Crystal
I128_0 = 0.to_i128

freq = {"" => 0}.clear
flagfields = [""].clear
File.open(ARGV[0]).each_line {|l|
  if l =~ /\/([^\.\s]+)$/
    flagfields.push($1)
    freq[$1] = freq.fetch($1, 0) + 1
  end
}

#pp freq

alphabet = {'a' => true}.clear
freq.each {|k, v|
  k.chars.each {|ch|
    alphabet[ch] = true
  }
}

idx_to_name = alphabet.keys.sort.uniq
name_to_idx = {'a' => 0}.clear
idx_to_name.each_with_index {|val, idx| name_to_idx[val] = idx }

data = [{flagfield: "", val: I128_0}].clear

flagfields.sort.uniq.each {|val|
  valint = I128_0
  val.each_char {|ch|
    valint |= ((I128_0 + 1) << name_to_idx[ch])
  }
  data.push({flagfield: val, val: valint})
}

#pp data

data2 = [{flagfield: "", saving: 0}].clear

0.upto(data.size - 1) do |i|
  saving = 0
  0.upto(data.size - 1) do |j|
    if (data[j][:val] & data[i][:val]) == data[i][:val]
      # i is a full subset of j
      saving += (data[i][:flagfield].size - 1) * freq[data[j][:flagfield]]
    end
  end
#  saving = (data[i][:flagfield].size - 1) * freq[data[j][:flagfield]]
  data2.push({flagfield: data[i][:flagfield], saving: saving})
end

# pp data2

data3 = data2.sort {|a, b| b[:saving] <=> a[:saving] }.first(10)

data3.each {|x|
  STDERR.puts x
}

# Find an unused flag
flag = ""
"!\"$%&'()*+,-./0123456789:;<=>@ABCDEFGHIJKLMNOPQRSTUVWXYZ[\\]^_`abcdefghijklmnopqrstuvwxyz{|}~".each_char do |ch|
  if !freq.has_key?(ch)
    flag = ch
    break
  end
end

out = [""].clear
rulestomerge = data3[0][:flagfield]
File.open(ARGV[1]).each_line {|l|
  if l =~ /\#\s+tf\=/ && l =~ /SFX\s+(\S+)/ && rulestomerge.index($1)
    out.push(l.strip.sub(/SFX\s+(\S+)/, "SFX #{flag}"))
  end
}
puts
puts "SFX #{flag} Y #{out.size}"
out.each {|l| puts l }
# pp freq.to_a.sort {|a, b| a[1] <=> b[1] }
