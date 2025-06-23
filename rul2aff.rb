#!/usr/bin/env ruby
# Copyright © 2025 Siarhei Siamashka
# SPDX-License-Identifier: CC-BY-SA-3.0+ OR MIT

MINSTRIP_PFX   = 0
MINADD_PFX     = 1
MINSTRIP_SFX   = 1
MINADD_SFX     = 1
MINPF          = 50

# 15 possible flags
flagspool_pfx = "0123456789+-*%="
# 52 possible flags
flagspool_sfx = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz"

class TrieNode
  def children     ; @children end
  def affixes      ; @affixes end

  @affixes = [{strip: "", add: "", freq: 0, pfreq: 0, str: ""}].clear
  def initialize
    @children = {'a' => self || TrieNode.new}.clear
    @affixes = [{strip: "", add: "", freq: 0, pfreq: 0, str: ""}].clear
  end
end

class Trie
  @pfstat = {"" => {freq: 0, pfreq: 0}}

  def initialize
    @pfstat = {"" => {freq: 0, pfreq: 0}}
    @root = TrieNode.new
  end

  def insert(str) # strip, add, freq)
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

    node = @root
    strip.each_char do |char|
      next unless children = node.children
      children[char] ||= TrieNode.new
      node = children[char]
    end
    node.affixes.push({strip: strip, add: add, freq: freq, pfreq: pfreq, str: str})
  end

  def dfs_sort(node = @root)
    children = node.children
    return unless children
    children.each_value {|child| dfs_sort(child) }
    node.affixes.sort! {|a, b| b[:freq] == a[:freq] ? b[:pfreq] <=> a[:pfreq] : b[:freq] <=> a[:freq] }
  end

  def dfs(remove = true, node = @root)
    total_child_freq = 0.0
    total_child_strs = [""].clear

    children = node.children
    return 0, [""].clear unless children

    child_weight_k = 1.0
    children.each_value do |child|
      child_freq, child_strs = dfs(false, child)
      total_child_freq += (child_freq || 0) * child_weight_k
      child_weight_k *= 0.0
      total_child_strs += child_strs
    end

    if node.affixes.size > 0
      if total_child_freq >= (node.affixes.first[:freq] || 0)
        children.each_value {|child| dfs(true, child) } if remove
        return total_child_freq.to_i, total_child_strs
      else
        if remove
          tmp = node.affixes.shift
          return tmp[:freq], [tmp[:str]]
        else
          return node.affixes.first[:freq], [node.affixes.first[:str]]
        end
      end
    end

    children.each_value {|child| dfs(true, child) } if remove
    return total_child_freq.to_i, total_child_strs
  end
end

input = File.open(ARGV[0])

sfx = Trie.new
pfx = Trie.new
input.each_line do |l|
  if l =~ /^PFX/
    pfx.insert(l)
  else
    sfx.insert(l)
  end
end

sfx.dfs_sort
pfx.dfs_sort

puts "SET UTF-8"
puts "WORDCHARS -’"

flagspool_pfx.chars.each do |ch|
  freq, data = pfx.dfs
  if data.size > 0
    puts "\nPFX #{ch} Y #{data.size}"
    data.each do |str|
      puts str.sub(/\?/, ch)
    end
  end
end

flagspool_sfx.chars.each do |ch|
  freq, data = sfx.dfs
  if data.size > 0
    puts "\nSFX #{ch} Y #{data.size}"
    data.each do |str|
      puts str.sub(/\?/, ch)
    end
  end
  puts
end
