#!/usr/bin/env ruby
# Copyright © 2025 Siarhei Siamashka
# SPDX-License-Identifier: CC-BY-SA-3.0+ OR MIT

MINSTRIP_PFX    = 0
MINADD_PFX      = 1
MINSTRIP_SFX    = 1
MINADD_SFX      = 1
MINPF           = 3
GROUP_MERGEABLE = false

# 15 possible flags for prefixes
flagspool_pfx = "0123456789+-*%="
# 52 possible flags for suffixes
flagspool_sfx = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz"

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
    return if type == "SFX" && strip.size < MINSTRIP_SFX
    return if type == "SFX" && add.size < MINADD_SFX
    return if type == "PFX" && strip.size < MINSTRIP_PFX
    return if type == "PFX" && add.size < MINADD_PFX

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
          return if pfreq < MINPF
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
    node.affixes.each_with_index do |entry, idx|
      if cherry_pick.has_key?({mstrip: entry[:mstrip], madd: entry[:madd]})
        node.affixes.delete_at(idx) if remove
        return entry[:freq], [entry]
      end
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

input = File.open(ARGV[0])

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
puts "WORDCHARS -’"

def gen(trie, flagspool, mergeable, cmd)
flagspool.chars.each do |ch|
  freq, data = trie.dfs(false)
  cherry_pick = { {mstrip: "", madd: ""} => true }.clear
  data.each do |entry|
    k = {mstrip: entry[:mstrip], madd: entry[:madd]}
    cherry_pick[k] = true if mergeable[k].size > 1 && GROUP_MERGEABLE
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

gen(pfx, flagspool_pfx, mergeable_pfx, "PFX")
gen(sfx, flagspool_sfx, mergeable_sfx, "SFX")
