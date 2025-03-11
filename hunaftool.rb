#!/usr/bin/env ruby
# Copyright © 2025, Siarhei Siamashka
# Creative Commons Attribution-ShareAlike 4.0 International License
#
# hunaftool - automated conversion between plain text word lists
#             and .DIC files for Hunspell, tailoring them for some
#             already existing .AFF file.

VERSION = 0.2

###############################################################################

require "set"

# Remap words to the arrays of numbers for performance reasons.
# Each of these numbers is the character index in a lookup table.
class Alphabet
  def initialize(charlist = "")
    @char_to_idx = {'a' => 0}.clear
    @idx_to_char = ['a'].clear
    @finalized   = false
    encode_word(charlist)
  end

  def finalized_size
    @finalized = true
    @idx_to_char.size
  end

  def encode_word(word)
    word.each_char.map do |ch|
      unless @char_to_idx.has_key?(ch)
        raise "The character «#{ch}» is missing from the alphabet.\n" if @finalized
        @char_to_idx[ch] = @idx_to_char.size
        @idx_to_char.push(ch)
      end
      @char_to_idx[ch]
    end.to_a
  end

  def decode_word(word)
    word.map {|idx| @idx_to_char[idx] }.join
  end
end

def parse_condition(alphabet, condition)
  out = [[0]].clear
  condition.scan(/\[\^([^\]]*)\]|\[([^\]\^]*)\]|(.)/) do
    m1, m2, m3 = $~.captures
    out << if m1
      tmp = {0 => true}.clear
      alphabet.encode_word(m1).each {|idx| tmp[idx] = true }
      alphabet.finalized_size.times.select {|idx| !tmp.has_key?(idx) }.to_a
    elsif m2
      alphabet.encode_word(m2).sort.uniq
    else
      alphabet.encode_word(m3.to_s)
    end
  end
  out
end

# That's an affix rule, pretty much in the same format as in .AFF files
class Rule
  def initialize(flag = "?", stripping = [0], affix = [0], condition = "", rawsrc = "")
    @flag, @stripping, @affix, @condition, @rawsrc = flag, stripping, affix, condition, rawsrc
  end
  def flag       ; @flag      end
  def stripping  ; @stripping end
  def affix      ; @affix     end
  def condition  ; @condition end
  def rawsrc     ; @rawsrc    end
end

# That's a processed result of matching a rule. It may be adjusted
# depending on what is the desired result.
class AffixMatch
  def initialize(flag = "?", remove_left = 0, append_left = [0], remove_right = 0, append_right = [0], rawsrc = "")
    @flag, @remove_left, @append_left, @remove_right, @append_right, @rawsrc =
      flag, remove_left, append_left, remove_right, append_right, rawsrc
  end
  def flag         ; @flag               end
  def remove_left  ; @remove_left        end
  def append_left  ; @append_left        end
  def remove_right ; @remove_right       end
  def append_right ; @append_right       end
  def to_s         ; "«" + @rawsrc + "»" end
end

# Bit flags, which determine how the rules are applied
RULESET_SUFFIX     = 0
RULESET_PREFIX     = 1
RULESET_FROM_STEM  = 0
RULESET_TO_STEM    = 2
RULESET_TESTSTRING = 4

# This is a https://en.wikipedia.org/wiki/Trie data structure for efficient search.
class Ruleset
  def initialize(alphabet, opts = 0)
    @alphabet = (alphabet ? alphabet : Alphabet.new)
    @opts     = opts
    @rules    = [AffixMatch.new].clear
    @children = [self, nil].clear
  end
  def children     ; @children end
  def children=(x) ; @children = x end
  def rules        ; @rules    end
  def suffix?      ; (@opts & RULESET_PREFIX)  == 0 end
  def prefix?      ; (@opts & RULESET_PREFIX)  != 0 end
  def from_stem?   ; (@opts & RULESET_TO_STEM) == 0 end
  def to_stem?     ; (@opts & RULESET_TO_STEM) != 0 end

  private def add_rule_imp(trie_node, rule, condition, condition_idx)
    return unless condition
    if condition_idx == condition.size
      return unless trie_node
      trie_node.rules.push(rule)
    else
      condition[condition_idx].each do |ch_idx|
        return unless trie_node && (children = trie_node.children)
        trie_node.children = [nil] * @alphabet.finalized_size + [self] if children.empty?
        return unless children = trie_node.children
        children[ch_idx] = Ruleset.new(@alphabet) unless children[ch_idx]
        add_rule_imp(children[ch_idx], rule, condition, condition_idx + 1)
      end
    end
  end

  def add_rule(rule)
    if prefix? && to_stem?
      condition = rule.affix.map {|x| [x]} + parse_condition(@alphabet, rule.condition)
      match = AffixMatch.new(rule.flag, rule.affix.size, rule.stripping, 0, [0].clear, rule.rawsrc)
      add_rule_imp(self, match, condition, 0)
    elsif prefix? && from_stem?
      condition = rule.stripping.map {|x| [x]} + parse_condition(@alphabet, rule.condition)
      match = AffixMatch.new(rule.flag, rule.stripping.size, rule.affix, 0, [0].clear, rule.rawsrc)
      add_rule_imp(self, match, condition, 0)
    elsif suffix? && to_stem?
      condition = (parse_condition(@alphabet, rule.condition) + rule.affix.map {|x| [x]}).reverse
      match = AffixMatch.new(rule.flag, 0, [0].clear, rule.affix.size, rule.stripping, rule.rawsrc)
      add_rule_imp(self, match, condition, 0)
    elsif suffix? && from_stem?
      condition = (parse_condition(@alphabet, rule.condition) + rule.stripping.map {|x| [x]}).reverse
      match = AffixMatch.new(rule.flag, 0, [0].clear, rule.stripping.size, rule.affix, rule.rawsrc)
      add_rule_imp(self, match, condition, 0)
    end
  end

  def matched_rules(word)
    node = self
    node.rules.each {|rule| yield rule }
    if prefix?
      word.each do |ch|
        children = node.children
        return unless children && children.size > 0 && (node = children[ch])
        node.rules.each {|rule| yield rule }
      end
    elsif suffix?
      word.reverse_each do |ch|
        children = node.children
        return unless children && children.size > 0 && (node = children[ch])
        node.rules.each {|rule| yield rule }
      end
    end
  end
end

# Loader for the .AFF files
#
# Note: the alphabet needs to be known in advance or provided by
# the "TRY" directive in the .AFF file.

class AFF
  def initialize(aff_file, charlist = "", opt = RULESET_FROM_STEM)
    affdata = (((opt & RULESET_TESTSTRING) != 0) ? aff_file
                                                 : File.open(aff_file))
    @alphabet = Alphabet.new(charlist)
    @prefixes = Ruleset.new(@alphabet, RULESET_PREFIX + opt)
    @suffixes = Ruleset.new(@alphabet, RULESET_SUFFIX + opt)
    @fullstrip = false
    @vstemflag = ""
    flag = ""
    cnt = 0
    affdata.each_line do |l|
      if l =~ /^\s*TRY\s+(\S+)(.*)$/
        raise "Malformed TRY directive #{l.strip}.\n" if $2.strip.size > 0
        @alphabet.encode_word($1)
        @alphabet.finalized_size
      elsif l =~ /^(\s*)FULLSTRIP\s*(\s+.*)?$/
        raise "Malformed FULLSTRIP directive (indented).\n" unless $1 == ""
        @fullstrip = true
      elsif l =~ /^(\s*)NEEDAFFIX\s+(\S+)$/
        raise "Malformed NEEDAFFIX directive (indented).\n" unless $1 == ""
        @vstemflag = $2
      elsif cnt == 0 && l =~ /^\s*([SP])FX\s+(\S+)\s+Y\s+(\d+)\s*(.*)$/
        type = $1
        flag = $2
        cnt = $3.to_i
      elsif l =~ /^\s*([SP])FX\s+(\S+)\s+(\S+)\s+(\S+)\s+(\S+)\s*(.*)$/
        type = $1
        unless flag == $2
          STDERR.puts "Invalid rule (flag mismatch): #{l}"
          next
        end
          if (cnt -= 1) < 0
          STDERR.puts "Invalid rule (wrong counter): #{l}"
          next
        end
        stripping = ($3 == "0" ? "" : $3)
        affix     = ($4 == "0" ? "" : $4)
        condition = ($5 == "." ? stripping : $5)
        unless condition =~ /#{stripping}$/
          STDERR.puts "Invalid rule (bad condition): #{l}"
          next
        end
        condition = condition.gsub(/#{stripping}$/, "")
        rule = Rule.new(flag, @alphabet.encode_word(stripping),
                        @alphabet.encode_word(affix), condition, l.strip)
        if type == "S"
          @suffixes.add_rule(rule)
        elsif type == "P"
          @prefixes.add_rule(rule)
        end
      end
    end

    # Prepare buffers for reuse without reallocating them
    @tmpbuf      = [0].clear
    @tmpbuf2     = [0].clear
  end

  def alphabet ; @alphabet end
  def prefixes ; @prefixes end
  def suffixes ; @suffixes end

  def tmpbuf_apply_prefix(encword, pfx)
    return false if encword.size == pfx.remove_left && !@fullstrip
    @tmpbuf.clear
    @tmpbuf.concat(pfx.append_left)
    (pfx.remove_left ... encword.size).each {|i| @tmpbuf << encword[i] }
    true
  end

  def tmpbuf_apply_suffix(encword, sfx)
    return false if encword.size == sfx.remove_right && !@fullstrip
    @tmpbuf.clear
    (0 ... encword.size - sfx.remove_right).each {|i| @tmpbuf << encword[i] }
    @tmpbuf.concat(sfx.append_right)
    true
  end

  # decode a single line from a .DIC file
  def decode_dic_entry(line)
    if line =~ /^([^\/]+)\/?(\S*)/
      word_utf8, joined_flags = $~.captures
      word = @alphabet.encode_word((word_utf8 || "").strip)
      flags = Set.new((joined_flags || "").split(""))

      yield @alphabet.decode_word(word) unless flags === @vstemflag

      prefixes.matched_rules(word) do |pfx|
        # Handle single prefixes without any suffix
        if flags === pfx.flag && tmpbuf_apply_prefix(word, pfx)
          yield @alphabet.decode_word(@tmpbuf)
        end
      end

      suffixes.matched_rules(word) do |sfx|
        if flags === sfx.flag && tmpbuf_apply_suffix(word, sfx)

          # Handle single suffixes
          yield @alphabet.decode_word(@tmpbuf)

          # And try to also apply prefix after each successful suffix substitution
          prefixes.matched_rules(@tmpbuf) do |pfx|
            if flags === pfx.flag && (@tmpbuf.size != pfx.remove_left || @fullstrip)
              @tmpbuf2.clear
              @tmpbuf2.concat(pfx.append_left)
              (pfx.remove_left ... @tmpbuf.size).each {|i| @tmpbuf2 << @tmpbuf[i] }
              yield @alphabet.decode_word(@tmpbuf2)
            end
          end
        end
      end
    end
  end
end

###############################################################################

def convert_dic_to_txt(aff_file, dic_file, delimiter = nil, out_file = nil)
  aff = AFF.new(aff_file, "")
  wordlist = {"" => true}.clear
  stemwordlist = {"" => true}.clear
  firstline = true
  alreadywarned = false

  real_number_of_stems = 0
  expected_number_of_stems = -1
  File.open(dic_file).each_line do |l|
    l = l.strip
    if firstline
      firstline = false
      if l =~ /^\s*(\d+)\s*$/
        expected_number_of_stems = $1.to_i
        next
      else
        STDERR.puts "Malformed .DIC file: the words counter is missing."
        alreadywarned = true
      end
    end
    if expected_number_of_stems != -1 &&
             real_number_of_stems > expected_number_of_stems && !alreadywarned
      STDERR.puts "Malformed .DIC file: the words counter is too small."
      alreadywarned = true
    end
    if l.empty?
      STDERR.puts "Malformed .DIC file: an unexpected empty line."
      alreadywarned = true
    else
      if delimiter
        stemwordlist.clear
        aff.decode_dic_entry(l) {|word| stemwordlist[word] = true }
        if l =~ /^\s*([^\/\s]+)/ && stemwordlist.size > 1 && stemwordlist.has_key?($1)
          stemwordlist.delete($1)
          wordlist[$1 + delimiter + stemwordlist.keys.sort.join(delimiter)] = true
        else
          stemwordlist.each_key {|word| wordlist[word] = true }
        end
      else
        aff.decode_dic_entry(l) {|word| wordlist[word] = true }
      end
      real_number_of_stems += 1
    end
  end

  if out_file
    fh = File.open(out_file, "w")
    wordlist.keys.sort.each {|word| fh.puts word }
    fh.close
  else
    wordlist.keys.sort.each {|word| puts word }
  end
end

###############################################################################
# Tests for various tricky cases
###############################################################################

def test_dic_to_txt(affdata, input, expected_output)
  dict = (affdata + input).split("").sort.uniq.join
  output = [""].clear
  AFF.new(affdata, dict, RULESET_TESTSTRING).decode_dic_entry(input) do |word|
    output << word
  end
  output = output.sort.uniq
  affdata = affdata.split('\n').map {|x| "    " + x.strip }.join('\n')
  unless output == expected_output
    STDERR.puts "\nTest failed:"
    STDERR.puts "  Affix:\n#{affdata}"
    STDERR.puts "  Input:    #{input}"
    STDERR.puts "  Output:   #{output}"
    STDERR.puts "  Expected: #{expected_output}"
  end
end

def run_tests
  # tests for overlapping prefix/suffix substitutions
  # Hunspell is applying suffix first, and then prefix may 
  # match the newly formed intermediate word. Pay attention
  # to the "ааааа" -> "ааяв" -> "бюв" transition.
  test_dic_to_txt("PFX A Y 1
                   PFX A ааа ба ааа
                   SFX B Y 1
                   SFX B ааа ав ааа", "ааааа/AB",
                   ["ааааа", "ааав", "бааа", "бав"])

  test_dic_to_txt("PFX A Y 1
                   PFX A ааа бю ааа
                   SFX B Y 1
                   SFX B ааа ав ааа", "ааааа/AB",
                   ["ааааа", "ааав", "бюаа", "бюв"])

  test_dic_to_txt("PFX A Y 1
                   PFX A ааа ба ааа
                   SFX B Y 1
                   SFX B ааа яв ааа", "ааааа/AB",
                   ["ааааа", "ааяв", "бааа"]) # "бяв" is not supported!

  test_dic_to_txt("PFX A Y 1
                   PFX A аая бю аая
                   SFX B Y 1
                   SFX B ааа яв ааа", "ааааа/AB",
                   ["ааааа", "ааяв", "бюв"])

  # prefix replacement is done after suffix replacement
  test_dic_to_txt("PFX A Y 2
                   PFX A лыжка сьвіньня лыжка
                   PFX A лыж шчот лыж
                   SFX B Y 1
                   SFX B екар ыжка лекар", "лекар/AB",
                   ["лекар", "лыжка", "шчотка"])

  # compared to the previous test, FULLSTRIP enables the word "сьвіньня"
  test_dic_to_txt("FULLSTRIP
                   PFX A Y 2
                   PFX A лыжка сьвіньня лыжка
                   PFX A лыж шчот лыж
                   SFX B Y 1
                   SFX B екар ыжка лекар", "лекар/AB",
                   ["лекар", "лыжка", "сьвіньня", "шчотка"])

  # the NEEDAFFIX flag turns "лекар" into a "virtual" stem, which isn't a word
  test_dic_to_txt("NEEDAFFIX z
                   PFX A Y 2
                   PFX A лыжка сьвіньня лыжка
                   PFX A лыж шчот лыж
                   SFX B Y 1
                   SFX B екар ыжка лекар", "лекар/ABz",
                   ["лыжка", "шчотка"])
end

###############################################################################
# Parse command line options
###############################################################################

verbose = false
input_format = "unk"
output_format = "unk"

args = ARGV.select do |arg|
  if arg =~ /^\-v$/
    verbose = true
    nil
  elsif arg =~ /^\-i\=(\S+)$/
    input_format = $1
    nil
  elsif arg =~ /^\-o\=(\S+)$/
    output_format = $1
    nil
  elsif arg =~ /^\-/
    abort "Unrecognized command line option: '#{arg}'\n"
  else
    arg
  end
end

unless args.size >= 1 && args[0] =~ /\.aff$/i && File.exists?(args[0])
  puts "hunaftool v#{VERSION} - automated conversion between plain text word lists"
  puts "                 and .DIC files for Hunspell, tailoring them for some"
  puts "                 already existing .AFF file."
  puts
  puts "Usage: ruby hunaftool.rb [options] <whatever.aff> [input_file] [output_file]"
  puts "Where options can be:"
  puts "  -v                      : verbose diagnostic messages to stderr"
  puts
  puts "  -i=[dic|txt|csv]        : the input file format:"
  puts "                             * txt - plain wordlist (TODO)"
  puts "                             * dic - dic file with word stems"
  puts
  puts "  -o=[dic|txt|csv|js|lua] : the desired output file format:"
  puts "                             * txt - text file with one word per line,"
  puts "                                     all words are unique and presented"
  puts "                                     in a sorted order."
  puts "                             * csv - text file with one stem per line,"
  puts "                                     followed by the comma separated"
  puts "                                     words that had been derived from"
  puts "                                     it via applying affixes."
  puts "                             * dic - dic file with word stems (TODO)"
  puts "                             * js  - JavaScript code (TODO)"
  puts "                             * lua - Lua code (TODO)"
  puts
  puts "An example of extracting all words from a dictionary:"
  puts "    ruby hunaftool.rb -i=dic -o=txt be_BY.aff be_BY.dic be_BY.txt"
  run_tests
  exit 0
end

# Automatically guess the input/output format from the file extension
input_format="dic" if input_format == "unk" && args.size >= 2 && args[1] =~ /\.dic$/i
input_format="txt" if input_format == "unk" && args.size >= 2 && args[1] =~ /\.txt$/i
input_format="csv" if input_format == "unk" && args.size >= 2 && args[1] =~ /\.csv$/i
output_format="dic" if output_format == "unk" && args.size >= 3 && args[2] =~ /\.dic$/i
output_format="txt" if output_format == "unk" && args.size >= 3 && args[2] =~ /\.txt$/i
output_format="csv" if output_format == "unk" && args.size >= 3 && args[2] =~ /\.csv$/i

# Default to the comma separated text output
output_format = "csv" if output_format == "unk" && args.size == 2 && input_format == "dic"

###############################################################################

if input_format == "dic" && output_format == "txt" && args.size >= 2
  convert_dic_to_txt(args[0], args[1], nil, (args.size >= 3 ? args[2] : nil))
  exit 0
end

if input_format == "dic" && output_format == "csv" && args.size >= 2
  convert_dic_to_txt(args[0], args[1], ", ", (args.size >= 3 ? args[2] : nil))
  exit 0
end

abort "Don't know how to convert from '#{input_format}' to '#{output_format}'."
