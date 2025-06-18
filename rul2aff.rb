#!/usr/bin/env ruby
# Copyright © 2025 Siarhei Siamashka
# SPDX-License-Identifier: CC-BY-SA-3.0+ OR MIT

MINSTRIP_SFX = 1
MINADD_SFX   = 1
MINPF        = 5

# 62 possible flags
flagspool = "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz"

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
    return unless str =~ /^([PS]FX)\s+\?\s+(\S+)\s+(\S+)\s+\.\s+\#\s*(.*)/
    type  = $1
    strip = (type == "SFX" ? $2.reverse : $2)
    add   = $3
    strip = "" if strip == "0"
    add = "" if add == "0"
    return if type == "SFX" && strip.size < MINSTRIP_SFX
    return if type == "SFX" && add.size < MINADD_SFX

    freq = 0
    pfreq = 0
    extradata = $4.split(/\s*,\s*/)
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

sfx = Trie.new
input.each_line do |l|
  sfx.insert(l)
end

sfx.dfs_sort

log_rejected = nil
if ARGV.size >= 2
  log_rejected = File.open(ARGV[1], "w")
end

puts "SET UTF-8"
puts "FULLSTRIP"
puts "WORDCHARS -ʼ’'"

flagspool.chars.each do |ch|
  freq, data = sfx.dfs
  break if data.size == 0

  puts "\nSFX #{ch} Y #{data.size}"
  data.each do |str|
    puts str.sub(/\?/, ch)
  end
end

if log_rejected
  log_rej_lines = [{str: "", freq: 0}].clear
  128.times do
    freq, data = sfx.dfs
    break if data.size == 0
    data.each do |str|
      if str =~ /\# tf=(\d+)/
        log_rej_lines.push({str: str, freq: $1.to_i})
      end
    end
  end
  log_rej_lines.sort {|a, b| b[:freq] <=> a[:freq] }.each {|l| log_rejected.puts l[:str] }
  log_rejected.close
end
