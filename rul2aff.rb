#!/usr/bin/env ruby
# Copyright © 2025 Siarhei Siamashka
# SPDX-License-Identifier: CC-BY-SA-3.0+ OR MIT

###############################################################################
# Parse command line options
###############################################################################

module Cfg
  @@verbose = false

  # Set the minimal desired size of the 'stripping' field of the prefix rule
  # entries. This can be used to disallow zero stripping rules, which might
  # be not very good for the speed of the process of dictionary generation.
  @@minstrip_pfx = 0

  # Set the minimal desired size of the 'affix' field of the prefix rule
  # entries. This can be used to disallow zero affix rules, which might
  # be not very good for the speed of the spellchecking by hunspell using
  # the generated dictionary.
  @@minadd_pfx   = 1

  # Set the minimal desired size of the 'stripping' field of the suffix rule
  # entries. This can be used to disallow zero stripping rules, which might
  # be not very good for the speed of the process of dictionary generation.
  @@minstrip_sfx = 1

  # Set the minimal desired size of the 'affix' field of the suffix rule
  # entries. This can be used to disallow zero affix rules, which might
  # be not very good for the speed of the spellchecking by hunspell using
  # the generated dictionary.
  @@minadd_sfx   = 1

  # Set the minimal theoretical frequency cutoff point for the data loaded
  # from the raw .rul files. This can be used to optimize the resources usage
  # during dictionary generation. For example, it obviously makes no sense
  # to have a rule for samething that occurs only once in the dictionary,
  # but the cutoff point can be set much higher than that. The frequency
  # is theoretical (the rule can be used to construct that many words in
  # the dictionary, but it's unlikely to be used that many times in
  # practice due to the competition with other rules).
  @@minfreq_theoretical = 2

  # Set the minimal practical frequency cutoff point for the data loaded
  # from the pre-filtered .rul files. This is based on the real measured
  # frequency of the affix rules usage, based on the preliminary dictionary
  # testing. Beware that the low value of the measured real frequency
  # doesn't necessarily mean that the rule is completely useless, especially
  # if it has a high theoretical frequency value. Some other competing
  # rules might be just stealing the spotlight and this rule might still
  # have its chance to shine in other circumstances.
  @@minfreq_real        = 2

  # The pool of the available affix flags for prefixes. Each of the flags can
  # be a single UTF-8 character, but ASCII is preferred for compact storage.
  @@flagspool_pfx       = "0123456789"

  # The pool of the available affix flags for suffixes. Each of the flags can
  # be a single UTF-8 character, but ASCII is preferred for compact storage.
  @@flagspool_sfx       = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz"

  @@group_mergeable     = false

  def self.verbose?            ; @@verbose end
  def self.verbose=(v)         ; @@verbose = v end
  def self.minstrip_pfx        ; @@minstrip_pfx end
  def self.minstrip_pfx=(v)    ; @@minstrip_pfx = v end
  def self.minadd_pfx          ; @@minadd_pfx end
  def self.minadd_pfx=(v)      ; @@minadd_pfx = v end
  def self.minstrip_sfx        ; @@minstrip_sfx end
  def self.minstrip_sfx=(v)    ; @@minstrip_sfx = v end
  def self.minadd_sfx          ; @@minadd_sfx end
  def self.minadd_sfx=(v)      ; @@minadd_sfx = v end

  def self.minfreq_real        ; @@minfreq_real end
  def self.minfreq_real=(v)    ; @@minfreq_real = v end
  def self.group_mergeable?    ; @@group_mergeable end
  def self.group_mergeable=(v) ; @@group_mergeable = v end

  def self.flagspool_pfx       ; @@flagspool_pfx end
  def self.flagspool_pfx=(v)   ; @@flagspool_pfx = v end
  def self.flagspool_sfx       ; @@flagspool_sfx end
  def self.flagspool_sfx=(v)   ; @@flagspool_sfx = v end
end

args = ARGV.select do |arg|
  if arg =~ /^\-v$/
    Cfg.verbose = true
    nil
  elsif arg =~ /^\-g$/
    Cfg.group_mergeable = true
    nil
  elsif arg =~ /^\-\-minstrip\-pfx=(\d+)$/
    Cfg.minstrip_pfx = $1.to_i
    nil
  elsif arg =~ /^\-\-minadd\-pfx=(\d+)$/
    Cfg.minadd_pfx = $1.to_i
    nil
  elsif arg =~ /^\-\-minstrip\-sfx=(\d+)$/
    Cfg.minstrip_sfx = $1.to_i
    nil
  elsif arg =~ /^\-\-minadd\-sfx=(\d+)$/
    Cfg.minadd_sfx = $1.to_i
    nil
  elsif arg =~ /^\-\-minfreq\-real=(\d+)$/
    Cfg.minfreq_real = $1.to_i
    nil
  elsif arg =~ /^\-\-flagspool\-pfx=(\S+)$/
    tmp = $1
    unless tmp.chars.sort.uniq.join.size == tmp.size
      STDERR.puts "! '#{tmp}' isn't a valid list of UTF-8 characters without duplicates."
      exit 1
    end
    Cfg.flagspool_pfx = tmp
    nil
  elsif arg =~ /^\-\-flagspool\-sfx=(\S+)$/
    tmp = $1
    unless tmp.chars.sort.uniq.join.size == tmp.size
      STDERR.puts "! '#{tmp}' isn't a valid list of UTF-8 characters without duplicates."
      exit 1
    end
    Cfg.flagspool_sfx = tmp
    nil
  elsif arg =~ /^\-\-autoflags=(\d+),(\d+)$/
    num_pfx = $1.to_i
    num_sfx = $2.to_i
    # the list of non-problematic characters that encode into one byte in UTF-8 representation
    goodflags = "!\"$%&'()*+,-0123456789:;<=>@ABCDEFGHIJKLMNOPQRSTUVWXYZ[\\]^_`abcdefghijklmnopqrstuvwxyz{|}~"
    goodsize = goodflags.size
    if num_pfx + num_sfx > goodsize
      abort "! The total number of autoassigned flags must not exceed #{goodsize}.\n"
    end
    if num_sfx <= 26 * 2 && num_pfx <= 14
      # nicer looking flags
      Cfg.flagspool_pfx = "0123456789+-*%"[0 ... num_pfx]
      Cfg.flagspool_sfx = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz"[0 ... num_sfx]
    else
      # only care about assigning a sufficient number of flags to get the job done
      Cfg.flagspool_pfx = goodflags[0 ... num_pfx]
      Cfg.flagspool_sfx = goodflags[num_pfx ... num_pfx + num_sfx]
    end
    nil
  elsif arg =~ /^\-/
    abort "Unrecognized command line option: '#{arg}'\n"
  else
    arg
  end
end

unless args.size >= 1
  puts "rul2aff"
  puts "Copyright © 2025 Siarhei Siamashka. License: CC-BY-SA or MIT."
  puts
  puts "Usage: rul2aff [options] <whatever.rul> > [output_file]"
  puts
  exit 0
end

class TrieNode
  def children     ; @children end
  def affixes      ; @affixes end

  @affixes = [{strip: "", add: "", mstrip: "", madd: "", freq: 0, pfreq: 0, str: ""}].clear
  def initialize
    @children = {'a' => self || TrieNode.new}.clear
    @affixes = [{strip: "", add: "", mstrip: "", madd: "", freq: 0, pfreq: 0, str: ""}].clear
  end
end

class Trie
  @pfstat = {"" => {freq: 0, pfreq: 0}}

  def root ; @root end

  def initialize
    @pfstat = {"" => {freq: 0, pfreq: 0}}
    @root = TrieNode.new
  end

  def parse(str)
    return unless str =~ /^([PS]FX)\s+\?\s+(\S+)\s+(\S+)\s+(\S+)\s+\#\s*(.*)/
    type  = $1
    strip = (type == "SFX" ? $2.reverse : $2)
    add   = $3
    strip = "" if strip == "0"
    add = "" if add == "0"
    return if type == "SFX" && strip.size < Cfg.minstrip_sfx
    return if type == "SFX" && add.size < Cfg.minadd_sfx
    return if type == "PFX" && strip.size < Cfg.minstrip_pfx
    return if type == "PFX" && add.size < Cfg.minadd_pfx

    tmp1 = strip.chars
    tmp1 = tmp1.reverse if type == "SFX"
    tmp2 = add.chars
    if type == "PFX"
      tmp1 = tmp1.reverse
      tmp2 = tmp2.reverse
    end
    while tmp1.size > 0 && tmp2.size > 0 && tmp1[0] == tmp2[0]
      tmp1.shift
      tmp2.shift
    end
    mstrip = tmp1.join
    madd = tmp2.join

    cond = $4
    if cond == "."
      cond = strip
    else
      cond = cond.reverse if type == "SFX"
    end
    abort "! malformed '#{str}'\n" unless cond == strip

    freq = 0
    pfreq = 0
    extradata = $5.split(/\s*,\s*/)
    extradata.each do |entry|
      if entry =~ /(.*)=(.*)/
        varname = $1
        varval  = $2
        if varname == "tf"
          freq = varval.to_i
        elsif varname == "pf"
          pfreq = varval.to_i
          @pfstat[strip + "/" + add] = {freq: freq, pfreq: pfreq}
          if @pfstat.has_key?(add + "/" + strip)
            if type == "SFX"
              STDERR.puts "! #{add}/#{strip.reverse} #{@pfstat[add + "/" + strip]} vs. #{strip.reverse}/#{add} #{@pfstat[strip + "/" + add]}"
            else
              STDERR.puts "! #{add}/#{strip} #{@pfstat[add + "/" + strip]} vs. #{strip}/#{add} #{@pfstat[strip + "/" + add]}"
            end
          end
          return if pfreq < Cfg.minfreq_real
        else
          STDERR.puts "! Unrecognized variable «#{varname}» in «#{str}»"
        end
      end
    end
    return {strip: strip, add: add, mstrip: mstrip, madd: madd, freq: freq, pfreq: pfreq, str: str}
  end

  def insert(entry)
    node = @root
    entry[:strip].each_char do |char|
      next unless children = node.children
      children[char] ||= TrieNode.new
      node = children[char]
    end
    node.affixes.push(entry)
  end

  def dfs_sort(node = @root)
    children = node.children
    return unless children
    children.each_value {|child| dfs_sort(child) }
    node.affixes.sort! {|a, b| b[:freq] == a[:freq] ? b[:pfreq] <=> a[:pfreq] : b[:freq] <=> a[:freq] }
  end

  def dfs(remove = true, node = @root, cherry_pick = { {mstrip: "", madd: ""} => true })
    if node.affixes.size > 0
      cherry_picked = [node.affixes.first].clear
      node.affixes.reject! do |entry|
        if cherry_pick.has_key?({mstrip: entry[:mstrip], madd: entry[:madd]})
          cherry_picked.push(entry)
          remove
        end
      end
      return cherry_picked.map {|entry| entry[:freq] }.sum, cherry_picked if cherry_picked.size > 0
    end

    total_child_freq = 0
    total_child_entr = [{strip: "", add: "", mstrip: "", madd: "", freq: 0, pfreq: 0, str: ""}].clear

    children = node.children
    return 0, total_child_entr unless children

    child_weight_k = 1.0
    children.each_value do |child|
      child_freq, child_entr = dfs(false, child, cherry_pick)
      total_child_freq += (child_freq || 0) * child_weight_k
      child_weight_k *= 0.0
      total_child_entr += child_entr
    end

    if node.affixes.size > 0
      if total_child_freq >= (node.affixes.first[:freq] || 0)
        children.each_value {|child| dfs(true, child, cherry_pick) } if remove
        return total_child_freq.to_i, total_child_entr
      else
        if remove
          tmp = node.affixes.shift
          return tmp[:freq], [tmp]
        else
          return node.affixes.first[:freq], [node.affixes.first]
        end
      end
    end

    children.each_value {|child| dfs(true, child, cherry_pick) } if remove
    return total_child_freq.to_i, total_child_entr
  end
end

input = File.open(args[0])

sfx = Trie.new
pfx = Trie.new

parsed_pfx = { {strip: "", add: "", mstrip: "", madd: "", freq: 0, pfreq: 0, str: ""} => true }.clear
parsed_sfx = { {strip: "", add: "", mstrip: "", madd: "", freq: 0, pfreq: 0, str: ""} => true }.clear
mergeable_pfx = { {mstrip: "", madd: ""} => { {strip: "", add: "", mstrip: "", madd: "", freq: 0, pfreq: 0, str: ""} => true } }.clear
mergeable_sfx = { {mstrip: "", madd: ""} => { {strip: "", add: "", mstrip: "", madd: "", freq: 0, pfreq: 0, str: ""} => true } }.clear

input.each_line do |l|
  if l =~ /^PFX/
    if entry = pfx.parse(l)
      parsed_pfx[entry] = true
    end
  else
    if entry = sfx.parse(l)
      parsed_sfx[entry] = true
    end
  end
end

parsed_pfx.each_key do |entry|
  mergeable_pfx[{mstrip: entry[:mstrip], madd: entry[:madd]}] ||= {entry => true}
  mergeable_pfx[{mstrip: entry[:mstrip], madd: entry[:madd]}][entry] = true
  pfx.insert(entry)
end

parsed_sfx.each_key do |entry|
  mergeable_sfx[{mstrip: entry[:mstrip], madd: entry[:madd]}] ||= {entry => true}
  mergeable_sfx[{mstrip: entry[:mstrip], madd: entry[:madd]}][entry] = true
  sfx.insert(entry)
end

pfx.dfs_sort
sfx.dfs_sort

puts "SET UTF-8"
puts "FLAG UTF-8"
puts "FULLSTRIP"
puts "WORDCHARS 0123456789-’"

def gen(trie, flagspool, mergeable, cmd)
flagspool.chars.each do |ch|
  freq, data = trie.dfs(false)
  cherry_pick = { {mstrip: "", madd: ""} => true }.clear
  data.each do |entry|
    k = {mstrip: entry[:mstrip], madd: entry[:madd]}
    cherry_pick[k] = true if mergeable[k].size > 1 && Cfg.group_mergeable?
  end
  if data.size > 0
    freq, data = trie.dfs(true, trie.root, cherry_pick)
    puts "\n#{cmd} #{ch} Y #{data.size}"
    data.sort {|a, b| a[:madd] == b[:madd] ? a[:strip] <=> b[:strip] : a[:madd] <=> b[:madd] }.each do |entry|
      puts entry[:str].sub(/\?/, ch)
    end
  end
end
end

gen(pfx, Cfg.flagspool_pfx, mergeable_pfx, "PFX")
gen(sfx, Cfg.flagspool_sfx, mergeable_sfx, "SFX")
