#!/usr/bin/env ruby
# Copyright © 2025 Siarhei Siamashka
# SPDX-License-Identifier: CC-BY-SA-4.0 OR MIT
#
# hunaftool - automated conversion between plain text word lists
#             and .DIC files for Hunspell, tailoring them for some
#             already existing .AFF file.

VERSION = 0.3

###############################################################################

require "set"

###############################################################################
# This tool is implemented using a common subset of Ruby and Crystal
# programming languages, so it shares the benefits of both:
#
#  * the tool can be easily run on any platform using a popular Ruby
#    interpreter.
#
#  * the tool can be compiled to a high-performance native executable on the
#    platforms, where Crystal compiler (https://crystal-lang.org) is available.
#
# See: https://crystal-lang.org/reference/1.15/crystal_for_rubyists/index.html
#      https://crystal-lang.org/reference/1.15/syntax_and_semantics/union_types.html
#
# Crystal language needs type annotations for empty containers. So instead of
# just declaring a generic empty array as "a = []", we need something move
# elaborate:
#
#   a = [0].clear       - an empty array of integers
#   a = [""].clear      - an empty array of strings
#   a = ["", 0].clear   - an empty array that can store integers or strings
#                         (the Crystal's union type, see the link above)
#
# Basically, if we need an empty container, then we create it with a single
# "sample" element for the Crystal compiler to get an idea about its type.
# And then instantly erase the content of this container to have it empty,
# readily available for future use.
###############################################################################

U8_0 = "\0".bytes.first   # 8-bit zero constant for Crystal compatibility
                          # to hint the usage of UInt8 instead of Int32

###############################################################################
# Remap UTF-8 words to indexable 8-bit arrays for performance reasons. All
# characters of the alphabet are consecutively numbered starting from 0 with
# no gaps or holes. This allows to have much faster array lookups instead
# of hash lookups when navigating a https://en.wikipedia.org/wiki/Trie
# data structure.
###############################################################################

class Alphabet
  def initialize(charlist = "")
    @char_to_idx = {'a' => U8_0}.clear
    @idx_to_char = ['a'].clear
    @finalized   = false
    encode_word(charlist)
  end

  def finalized_size
    @finalized = true
    @idx_to_char.size
  end

  # Convert an UTF-8 string to a 8-bit array
  def encode_word(word)
    out = "".bytes
    word.each_char do |ch|
      unless @char_to_idx.has_key?(ch)
        if @finalized
          raise "Bad character «#{ch}». Add it to the alphabet via TRY directive in .AFF\n"
        end
        @char_to_idx[ch] = U8_0 + @idx_to_char.size
        @idx_to_char << ch
      end
      out << @char_to_idx[ch]
    end
    out
  end

  # Convert a 8-bit array back to an UTF-8 string
  def decode_word(word)
    word.map {|idx| @idx_to_char[idx] }.join
  end
end

def parse_condition(alphabet, condition)
  out = ["".bytes].clear
  condition.scan(/\[\^([^\]]*)\]|\[([^\]\^]*)\]|(.)/) do
    m1, m2, m3 = $~.captures
    out << if m1
      tmp = {0 => true}.clear
      alphabet.encode_word(m1).each {|idx| tmp[idx] = true }
      alphabet.finalized_size.times.map {|x| U8_0 + x }.select {|idx| !tmp.has_key?(idx) }.to_a
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
  def initialize(flag = "?", stripping = "".bytes, affix = "".bytes, condition = "", rawsrc = "")
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
  def initialize(flag = "?", remove_left = 0, append_left = "".bytes, remove_right = 0, append_right = "".bytes, rawsrc = "")
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

# This is a https://en.wikipedia.org/wiki/Trie data structure for efficient search
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
      match = AffixMatch.new(rule.flag, rule.affix.size, rule.stripping, 0, "".bytes, rule.rawsrc)
      add_rule_imp(self, match, condition, 0)
    elsif prefix? && from_stem?
      condition = rule.stripping.map {|x| [x]} + parse_condition(@alphabet, rule.condition)
      match = AffixMatch.new(rule.flag, rule.stripping.size, rule.affix, 0, "".bytes, rule.rawsrc)
      add_rule_imp(self, match, condition, 0)
    elsif suffix? && to_stem?
      condition = (parse_condition(@alphabet, rule.condition) + rule.affix.map {|x| [x]}).reverse
      match = AffixMatch.new(rule.flag, 0, "".bytes, rule.affix.size, rule.stripping, rule.rawsrc)
      add_rule_imp(self, match, condition, 0)
    elsif suffix? && from_stem?
      condition = (parse_condition(@alphabet, rule.condition) + rule.stripping.map {|x| [x]}).reverse
      match = AffixMatch.new(rule.flag, 0, "".bytes, rule.stripping.size, rule.affix, rule.rawsrc)
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
    @prefixes_from_stem = Ruleset.new(@alphabet, RULESET_PREFIX + RULESET_FROM_STEM)
    @suffixes_from_stem = Ruleset.new(@alphabet, RULESET_SUFFIX + RULESET_FROM_STEM)
    @prefixes_to_stem   = Ruleset.new(@alphabet, RULESET_PREFIX + RULESET_TO_STEM)
    @suffixes_to_stem   = Ruleset.new(@alphabet, RULESET_SUFFIX + RULESET_TO_STEM)
    @fullstrip = false
    @virtual_stem_flag = ""
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
        @virtual_stem_flag = $2
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
          @suffixes_from_stem.add_rule(rule)
          @suffixes_to_stem.add_rule(rule)
        elsif type == "P"
          @prefixes_from_stem.add_rule(rule)
          @prefixes_to_stem.add_rule(rule)
        end
      end
    end

    # Prepare buffers for reuse without reallocating them
    @tmpbuf  = "".bytes
    @tmpbuf2 = "".bytes
  end

  def alphabet           ; @alphabet end
  def prefixes_from_stem ; @prefixes_from_stem end
  def suffixes_from_stem ; @suffixes_from_stem end
  def prefixes_to_stem   ; @prefixes_to_stem end
  def suffixes_to_stem   ; @suffixes_to_stem end
  def fullstrip?         ; @fullstrip end
  def virtual_stem_flag  ; @virtual_stem_flag end

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

      if @virtual_stem_flag.empty? || !(flags === @virtual_stem_flag)
        yield @alphabet.decode_word(word)
      end

      prefixes_from_stem.matched_rules(word) do |pfx|
        # Handle single prefixes without any suffix
        if flags === pfx.flag && tmpbuf_apply_prefix(word, pfx)
          yield @alphabet.decode_word(@tmpbuf)
        end
      end

      suffixes_from_stem.matched_rules(word) do |sfx|
        if flags === sfx.flag && tmpbuf_apply_suffix(word, sfx)

          # Handle single suffixes
          yield @alphabet.decode_word(@tmpbuf)

          # And try to also apply prefix after each successful suffix substitution
          prefixes_from_stem.matched_rules(@tmpbuf) do |pfx|
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

class WordData
  def initialize(encword = "".bytes)
    @encword  = encword
    @flags    = [""].to_set.clear
    @covers   = [0].to_set.clear
  end

  def encword       ; @encword end
  def flags         ; @flags end
  def covers        ; @covers end
end

###############################################################################

def convert_txt_to_dic(aff_file, txt_file, out_file = nil)
  aff = AFF.new(aff_file)

  # Load the text file into memory
  encword_to_idx = {"".bytes => 0}.clear
  idx_to_data = [WordData.new].clear
  File.open(txt_file).each_line do |line|
    next if (line = line.strip).empty? || line =~ /^#/
    line.split(/[\,\|]/).each do |word|
      word = word.strip
      encword = aff.alphabet.encode_word(word)
      next if encword_to_idx.has_key?(encword)
      encword_to_idx[encword] = idx_to_data.size
      idx_to_data.push(WordData.new(encword))
    end
  end

  # have normal words below this index, and virtual stems at it and above
  virtual_stem_area_begin = idx_to_data.size

  tmpbuf = "".bytes

  # Going from words to all possible stems (including the virtual stems that
  # aren't proper words themselves), find the prelimitary sets of flags that
  # can be potentially used to construct such words.
  (0 ... virtual_stem_area_begin).each do |idx|
    encword = idx_to_data[idx].encword
    aff.suffixes_to_stem.matched_rules(encword) do |sfx|
      next if encword.size == sfx.remove_right && !aff.fullstrip?

      tmpbuf.clear
      (0 ... encword.size - sfx.remove_right).each {|i| tmpbuf << encword[i] }
      tmpbuf.concat(sfx.append_right)

      if (stem_idx = encword_to_idx.fetch(tmpbuf, -1)) != -1
        idx_to_data[stem_idx].flags.add(sfx.flag)
      elsif !aff.virtual_stem_flag.empty?
        tmpbuf2 = tmpbuf.dup
        stem_idx = idx_to_data.size
        encword_to_idx[tmpbuf2] = idx_to_data.size
        data = WordData.new(tmpbuf2)
        data.flags.add(sfx.flag)
        idx_to_data.push(data)
      end
    end
  end

  # Going from stems to the affixed words that they produce, identify and
  # remove all invalid flags
  idx_to_data.each_with_index do |data, idx|
    next if data.flags.empty?
    encstem = data.encword
    aff.suffixes_from_stem.matched_rules(encstem) do |sfx|
      next if encstem.size == sfx.remove_right && !aff.fullstrip?
      next unless data.flags === sfx.flag

      tmpbuf.clear
      (0 ... encstem.size - sfx.remove_right).each {|i| tmpbuf << encstem[i] }
      tmpbuf.concat(sfx.append_right)

      if encword_to_idx.fetch(tmpbuf, virtual_stem_area_begin) >= virtual_stem_area_begin
        data.flags.delete(sfx.flag)
      end
    end
  end

  # Now that all flags are valid, retrive the full list of words that can
  # be generated from this stem
  idx_to_data.each_with_index do |data, idx|
    next if data.flags.empty?
    encstem = data.encword

    data.covers.add(idx) unless idx >= virtual_stem_area_begin

    aff.suffixes_from_stem.matched_rules(encstem) do |sfx|
      next if encstem.size == sfx.remove_right && !aff.fullstrip?
      next unless data.flags === sfx.flag

      tmpbuf.clear
      (0 ... encstem.size - sfx.remove_right).each {|i| tmpbuf << encstem[i] }
      tmpbuf.concat(sfx.append_right)

      if (tmpidx = encword_to_idx.fetch(tmpbuf, virtual_stem_area_begin)) < virtual_stem_area_begin
        data.covers.add(tmpidx)
      end
    end
  end

  # Greedily select those stems, which cover more words. In case of a tie, select the
  # shorter one
  order = idx_to_data.size.times.to_a.sort do |idx1, idx2|
    if idx_to_data[idx2].covers.size == idx_to_data[idx1].covers.size
      if idx_to_data[idx1].encword.size == idx_to_data[idx2].encword.size
        # Fallback to the alphabetic sort
        idx_to_data[idx1].encword <=> idx_to_data[idx2].encword
      else
        idx_to_data[idx1].encword.size <=> idx_to_data[idx2].encword.size
      end
    else
      idx_to_data[idx2].covers.size <=> idx_to_data[idx1].covers.size
    end
  end

  todo = [true] * virtual_stem_area_begin
  final_result = {"" => true}.clear

  # Produce output
  order.each do |idx|
    stem_is_virtual = (idx >= virtual_stem_area_begin)
    data = idx_to_data[idx]
    effectivelycovers = 0
    data.covers.each {|idx2| effectivelycovers += 1 if todo[idx2] }
    if effectivelycovers > 0 && !(stem_is_virtual && effectivelycovers == 1)
      final_result[aff.alphabet.decode_word(data.encword) +
                "/" + data.flags.to_a.sort.join +
                      (stem_is_virtual ? aff.virtual_stem_flag : "")] = true
      data.covers.each {|idx2| todo[idx2] = false }
    end
  end

  todo.each_index do |idx|
    if todo[idx]
      data = idx_to_data[idx]
      final_result[aff.alphabet.decode_word(data.encword)] = true
    end
  end

  if out_file
    fh = File.open(out_file, "w")
    fh.puts final_result.size
    final_result.keys.sort.each {|word| fh.puts word }
    fh.close
  else
    puts final_result.size
    final_result.keys.sort.each {|word| puts word }
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
  puts "                 already existing .AFF file with affixes."
  puts "Copyright © 2025 Siarhei Siamashka. License: CC BY-SA 4.0 or MIT."
  puts
  puts "Usage: hunaftool [options] <whatever.aff> [input_file] [output_file]"
  puts "Where options can be:"
  puts "  -v                      : verbose diagnostic messages to stderr"
  puts
  puts "  -i=[dic|txt|csv]        : the input file format:"
  puts "                             * txt - plain word list with one word per line"
  puts "                             * csv - same as txt, but more than one word"
  puts "                                     is allowed in a line and they are"
  puts "                                     comma separated"
  puts "                             * dic - a .DIC file from Hunspell"
  puts
  puts "  -o=[dic|txt|csv|js|lua] : the desired output file format:"
  puts "                             * txt - text file with one word per line,"
  puts "                                     all words are unique and presented"
  puts "                                     in a sorted order."
  puts "                             * csv - text file with one stem per line,"
  puts "                                     each of them followed by the comma"
  puts "                                     separated words that had been derived"
  puts "                                     from it via applying affixes."
  puts "                             * dic - a .DIC file for Hunspell"
  puts "                             * js  - JavaScript code (TODO)"
  puts "                             * lua - Lua code (TODO)"
  puts
  puts "An example of extracting all words from a dictionary:"
  puts "    ruby hunaftool.rb -i=dic -o=txt be_BY.aff be_BY.dic be_BY.txt"
  puts
  puts "An example of creating a .DIC file from an .AFF file and a word list:"
  puts "    ruby hunaftool.rb -i=txt -o=dic be_BY.aff be_BY.txt be_BY.dic"
  puts
  puts "If the input and output formats are not provided via -i/-o options,"
  puts "then they are automatically guessed from file extensions. If the"
  puts "output file is not provided, then the result is printed to stdout."
  puts
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

# Default to producing a .DIC file if only given text input
output_format = "dic" if output_format == "unk" && args.size == 2 &&
                         (input_format == "txt" || input_format == "csv")

###############################################################################

if input_format == "dic" && output_format == "txt" && args.size >= 2
  convert_dic_to_txt(args[0], args[1], nil, (args.size >= 3 ? args[2] : nil))
  exit 0
end

if input_format == "dic" && output_format == "csv" && args.size >= 2
  convert_dic_to_txt(args[0], args[1], ", ", (args.size >= 3 ? args[2] : nil))
  exit 0
end

if (input_format == "txt" || input_format == "csv") && output_format == "dic" && args.size >= 2
  convert_txt_to_dic(args[0], args[1], (args.size >= 3 ? args[2] : nil))
  exit 0
end

abort "Don't know how to convert from '#{input_format}' to '#{output_format}'."
