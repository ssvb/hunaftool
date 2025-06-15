#!/usr/bin/env ruby
# Copyright © 2025 Siarhei Siamashka
# SPDX-License-Identifier: CC-BY-SA-3.0+ OR MIT

suff_flags = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz"
pref_flags = "0123456789"
comb_flags = "!\"#$%&'()*+,-./:;<=>?@[\\]^_`{|}~"

suff_flags += pref_flags
suff_flags += comb_flags

suff_flags = suff_flags.chars.sort.uniq.first(75).join

class TrieNode
  def children     ; @children end
  def affixes      ; @affixes end

  @affixes = [{strip: "", add: "", freq: 0, str: ""}].clear
  def initialize
    @children = {'a' => self || TrieNode.new}.clear
    @affixes = [{strip: "", add: "", freq: 0, str: ""}].clear
  end
end

class Trie
  def initialize
    @root = TrieNode.new
  end

  def insert(str) # strip, add, freq)
    return unless str =~ /^([PS]FX)\s+\?\s+(\S+)\s+(\S+)\s+\.\s+\#(\d+)/
    type  = $1
    strip = (type == "SFX" ? $2.reverse : $2)
    add   = $3
    freq  = $4.to_i
    strip = "" if strip == "0"
    add = "" if add == "0"
    return if strip == "" || add == ""
    return if strip.size < 2
    node = @root
    strip.each_char do |char|
      next unless children = node.children
      children[char] ||= TrieNode.new
      node = children[char]
    end
    node.affixes.push({strip: strip, add: add, freq: freq, str: str})
  end

  def dfs(remove = true, node = @root)
    total_child_freq = 0
    total_child_strs = [""].clear

    children = node.children
    return 0, [""].clear unless children
      children.each_value do |child|
        child_freq, child_strs = dfs(false, child)
        total_child_freq += child_freq || 0
        total_child_strs += child_strs
      end

    if node.affixes.size > 0
      if total_child_freq >= (node.affixes.first[:freq] || 0)
        children.each_value {|child| dfs(true, child) } if remove
        return total_child_freq, total_child_strs
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
    return total_child_freq, total_child_strs
  end
end

input = File.open(ARGV[0])

t = Trie.new
input.each_line do |l|
  t.insert(l)
end

log_rejected = nil
if ARGV.size >= 2
  log_rejected = File.open(ARGV[1], "w")
end

puts "SET UTF-8"
puts "WORDCHARS -ʼ’'"

suff_flags.chars.each do |ch|
  freq, data = t.dfs
  break if data.size == 0

  puts "\nSFX #{ch} Y #{data.size}"
  data.each do |str|
    puts str.sub(/\?/, ch)
  end
end

if log_rejected
  # TODO
  suff_flags.chars.each do |ch|
    freq, data = t.dfs
    break if data.size == 0
    data.each do |str|
      log_rejected.puts str
    end
  end
end
