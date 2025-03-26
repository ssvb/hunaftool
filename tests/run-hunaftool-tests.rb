#!/usr/bin/env ruby
# Copyright © 2025 Siarhei Siamashka
# SPDX-License-Identifier: CC-BY-SA-3.0+ OR MIT
#
# Hunaftool's test suite.

require "find"
require "set"

def run_tests(dir, cmdlines)
  Find.find(dir) do |filename|
    next unless filename =~ /\.aff/i
    dicfile = filename.gsub(/\.aff/i, ".dic")
    txtfile = filename.gsub(/\.aff/i, ".txt")
    csvfile = filename.gsub(/\.aff/i, ".csv")
    goodfile = filename.gsub(/\.aff/i, ".good")
    goodfiledic = filename.gsub(/\.aff/i, ".good.dic")
    txtfile = csvfile unless File.exist?(txtfile)

    if File.exist?(dicfile) && File.exist?(goodfile)
      # .dic file decoding
      cmdlines.each do |cmdline|
        result = `#{cmdline} -o=txt #{filename} #{dicfile}`.lines.map {|l| l.strip }.sort
        expected = File.read(goodfile).lines.map {|l| l.strip }.sort
        if result != expected
          STDERR.puts "\n== Test «#{cmdline} -o=txt #{filename} #{dicfile}» failed:"
          STDERR.puts "== Expected: =="
          STDERR.puts expected.join("\n")
          STDERR.puts "== Got ==:"
          STDERR.puts result.join("\n")
          STDERR.puts
          exit 1
        end
      end
    elsif File.exist?(txtfile) && File.exist?(goodfiledic)
      # .dic file decoding
      cmdlines.each do |cmdline|
        result = `#{cmdline} -o=dic #{filename} #{txtfile}`.lines.map {|l| l.strip }.sort
        expected = File.read(goodfiledic).lines.map {|l| l.strip }
        if result != expected
          STDERR.puts "\n== Test «#{cmdline} -o=dic #{filename} #{txtfile}» failed:"
          STDERR.puts "== Expected: =="
          STDERR.puts expected.join("\n")
          STDERR.puts "== Got ==:"
          STDERR.puts result.join("\n")
          STDERR.puts
          exit 1
        end
      end
    end
  end
end

if ARGV.size < 2
  puts "This is a script for running the test suite."
  puts
  puts "Usage: run-hunaftool-tests [cmdline] [dir]"
  puts
  puts "Where:"
  puts "  cmdline - Hunaftool invocation cmdline (eg. \"ruby hunaftool.rb\")"
  puts "  dir     - a directory with testcases"
  exit 1
end

cmdline = ARGV[0]
dir = ARGV[1]

unless FileTest.directory?(dir)
  STDERR.puts "The supplied «#{dir}» argument is not a valid directory."
  exit 1
end

begin
  raise "" unless `#{cmdline}` =~ /hunaftool/i
rescue
  STDERR.puts "The supplied «#{cmdline}» argument is not a valid Hunaftool invocation cmdline."
  exit 1
end

run_tests(dir, [cmdline])

STDERR.puts "Tests passed."
exit 0
