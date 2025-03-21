#!/usr/bin/env ruby
# Copyright © 2025 Siarhei Siamashka
# SPDX-License-Identifier: CC-BY-SA-4.0 OR MIT
#
# hunaftool - automated conversion between plain text word lists
#             and .DIC files for Hunspell, tailoring them for some
#             already existing .AFF file.

VERSION = 0.7

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

# This is how runing under Crystal can be detected.
COMPILED_BY_CRYSTAL = (((1 / 2) * 2) != 0)

# An 8-bit zero constant to hint the use of UInt8 instead of Int32 for Crystal
U8_0 = "\0".bytes.first

# A 64-bit zero constant to hint the use of Int64 instead of Int32 for Crystal
I64_0 = (0x3FFFFFFFFFFFFFFF & 0)

###############################################################################
# Remap UTF-8 words to indexable 8-bit arrays for performance reasons. All
# characters of the alphabet are consecutively numbered starting from 0 with
# no gaps or holes. This allows to have much faster array lookups instead
# of hash lookups when navigating a https://en.wikipedia.org/wiki/Trie
# data structure.
###############################################################################

class AlphabetException < Exception
end

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
          STDERR.puts "! An unexpected character «#{ch}» encountered while processing «#{word}»."
          raise AlphabetException.new
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

def alphabet_from_file(filename)
  used_alphabet = {'A' => true}.clear
  File.open(filename).each_char {|ch| used_alphabet[ch] = true }
  return used_alphabet.keys.join
end

###############################################################################
# Parsing and management of the affix flags
#
# For a relatively small number of flags, it's possible to store all
# of them in the bits of a 64-bit integer variable. This works very
# fast and also reduces the memory footprint. Many real dictionaries
# don't need many flags. For example, the Belarusian dictionary at
# https://github.com/375gnu/spell-be-tarask only uses 44 distinct
# flags.
#
# But supporting a large number of flags is still necessary too. For
# example, to handle the AFF+DIC pairs produced by the "affixcompress"
# tool. The number of flags in these generated files may be 5000 or more.
#
# Note: the Ruby interpreter switches to a slow BigInt implementation for
#       anything that requires more than 62 bits, so the practical limit
#       is actually a bit lower.
###############################################################################

module AffFlags
  UTF8                      = 1    # "FLAG UTF-8" option in the affix file
  LONG                      = 2    # "FLAG long" option in the affix file
  NUM                       = 3    # "FLAG num" option in the affix file

  SWITCH_TO_HASH_THRESHOLD  = 63

  @@mode                  = UTF8
  @@flagname_s_to_bitpos  = {"A" => 0}.clear
  @@flagname_ch_to_bitpos = {'A' => 0}.clear
  @@bitpos_to_flagname    = ["A"].clear

  def self.mode ; @@mode end
  def self.mode=(newmode)
    @@mode = newmode
    @@flagname_s_to_bitpos.clear
    @@flagname_ch_to_bitpos.clear
    @@bitpos_to_flagname.clear
  end

  def self.flagname_to_bitpos(flag, flagfield)
    if flag.is_a?(String)
      if (bitpos = @@flagname_s_to_bitpos.fetch(flag, -1)) != -1
        return bitpos
      end
    else
      if (bitpos = @@flagname_ch_to_bitpos.fetch(flag, -1)) != -1
        return bitpos
      end
    end
    STDERR.puts "! Invalid flag «#{flag}» is referenced from the flags field «#{flagfield}»."
    return -1
  end

  def self.bitpos_to_flagname ; @@bitpos_to_flagname end
  def self.need_hash? ; @@bitpos_to_flagname.size >= SWITCH_TO_HASH_THRESHOLD end

  def self.register_flag(flagname)
    if @@mode == UTF8 && flagname.size > 1
      STDERR.puts "! The flag must be exactly one character, but «#{flagname}» is longer than that."
      flagname = flagname[0, 1]
    elsif @@mode == LONG && flagname.size != 2
      STDERR.puts "! The long flag must be exactly 2 characters, but «#{flagname}» is not compliant."
      return if flagname.size < 2
      flagname = flagname[0, 2]
    elsif @@mode == NUM && (!(flagname =~ /^(\d+)(.*)$/) || !$2.empty? || $1.to_i >= 65510)
      STDERR.puts "! The num flag must be a decimal number <= 65509, but «#{flagname}» is not compliant."
      abort "! It's too tricky to emulate this aspect of Hunspell's behaviour. Aborting...\n"
    end
    return if @@flagname_s_to_bitpos.has_key?(flagname)
    @@flagname_s_to_bitpos[flagname] = @@bitpos_to_flagname.size
    if flagname.size == 1
      @@flagname_ch_to_bitpos[flagname[0]] = @@bitpos_to_flagname.size
    end
    @@bitpos_to_flagname << flagname
  end
end

class String
  def to_aff_flags
    if AffFlags.need_hash?
      tmp = {-1 => true}
      case AffFlags.mode when AffFlags::LONG
        STDERR.puts "! The flags field «#{self}» must have an even number of characters." if size.odd?
        self.scan(/(..)/) { tmp[AffFlags.flagname_to_bitpos($1, self)] = true }
      when AffFlags::NUM then
        unless self.strip.empty?
          self.split(',').each {|chunk| tmp[AffFlags.flagname_to_bitpos(chunk.strip, self)] = true }
        end
      else
        self.each_char {|ch| tmp[AffFlags.flagname_to_bitpos(ch, self)] = true }
      end
      tmp.delete(-1)
      tmp
    else
      tmp = I64_0
      case AffFlags.mode when AffFlags::LONG
        STDERR.puts "! The flags field «#{self}» must have an even number of characters." if size.odd?
        self.scan(/(..)/) { tmp |= ((I64_0 + 1) << AffFlags.flagname_to_bitpos($1, self)) }
      when AffFlags::NUM then
        unless self.strip.empty?
          self.split(',').each {|chunk| tmp |= ((I64_0 + 1) << AffFlags.flagname_to_bitpos(chunk.strip, self)) }
        end
      else
        self.each_char {|ch| tmp |= ((I64_0 + 1) << AffFlags.flagname_to_bitpos(ch, self)) }
      end
      tmp
    end
  end
end

def aff_flags_to_s(flags)
  if flags.is_a?(Hash)
    flags.keys.map {|idx| AffFlags.bitpos_to_flagname[idx] }.sort
      .join((AffFlags.mode == AffFlags::NUM) ? "," : "")
  else
    AffFlags.bitpos_to_flagname
      .each_index.select {|idx| (((I64_0 + 1) << idx) & flags) != 0 }
      .map {|idx| AffFlags.bitpos_to_flagname[idx] }.to_a.sort
      .join((AffFlags.mode == AffFlags::NUM) ? "," : "")
  end
end

def aff_flags_empty?(flags)
  if flags.is_a?(Hash)
    flags.empty?
  else
    flags == 0
  end
end

def aff_flags_intersect?(flags1, flags2)
  if !flags1.is_a?(Hash) && !flags2.is_a?(Hash)
    (flags1 & flags2) != 0
  elsif flags1.is_a?(Hash) && flags2.is_a?(Hash)
    flags2.each_key {|k| return true if flags1.has_key?(k) }
    false
  else
    raise "aff_flags_intersect?(#{flags1}, #{flags2})\n"
  end
end

def aff_flags_merge!(flags1, flags2)
  if !flags1.is_a?(Hash) && !flags2.is_a?(Hash)
    flags1 |= flags2
  elsif flags1.is_a?(Hash) && flags2.is_a?(Hash)
    flags2.each_key {|k| flags1[k] = true }
    flags1
  else
    raise "aff_flags_merge!(#{flags1}, #{flags2})\n"
  end
end

def aff_flags_delete!(flags1, flags2)
  if !flags1.is_a?(Hash) && !flags2.is_a?(Hash)
    flags1 &= ~flags2
  elsif flags1.is_a?(Hash) && flags2.is_a?(Hash)
    flags2.each_key {|k| flags1.delete(k) }
    flags1
  else
    raise "aff_flags_delete!(#{flags1}, #{flags2})\n"
  end
end

###############################################################################

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
  def initialize(flag = I64_0, flag2 = I64_0, crossproduct = true,
                 stripping = "".bytes, affix = "".bytes, condition = "", rawsrc = "")
    @flag = {0 => true}.clear if AffFlags.need_hash?
    @flag2 = {0 => true}.clear if AffFlags.need_hash?
    @flag, @flag2, @crossproduct, @stripping, @affix, @condition, @rawsrc =
      flag, flag2, crossproduct, stripping, affix, condition, rawsrc
  end
  def flag       ; @flag      end
  def flag2      ; @flag2     end
  def cross      ; @crossproduct end
  def stripping  ; @stripping end
  def affix      ; @affix     end
  def condition  ; @condition end
  def rawsrc     ; @rawsrc    end
end

# That's a processed result of matching a rule. It may be adjusted
# depending on what is the desired result.
class AffixMatch
  def initialize(flag = I64_0, flag2 = I64_0, crossproduct = true,
                 remove_left = 0, append_left = "".bytes, remove_right = 0, append_right = "".bytes,
                 rawsrc = "")
    @flag = {0 => true}.clear if AffFlags.need_hash?
    @flag2 = {0 => true}.clear if AffFlags.need_hash?
    @flag, @flag2, @crossproduct, @remove_left, @append_left, @remove_right, @append_right, @rawsrc =
      flag, flag2, crossproduct, remove_left, append_left, remove_right, append_right, rawsrc
  end
  def flag         ; @flag               end
  def flag2        ; @flag2              end
  def cross        ; @crossproduct       end
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
      match = AffixMatch.new(rule.flag, rule.flag2, rule.cross,
                             rule.affix.size, rule.stripping, 0, "".bytes, rule.rawsrc)
      add_rule_imp(self, match, condition, 0)
    elsif prefix? && from_stem?
      condition = rule.stripping.map {|x| [x]} + parse_condition(@alphabet, rule.condition)
      match = AffixMatch.new(rule.flag, rule.flag2, rule.cross,
                             rule.stripping.size, rule.affix, 0, "".bytes, rule.rawsrc)
      add_rule_imp(self, match, condition, 0)
    elsif suffix? && to_stem?
      condition = (parse_condition(@alphabet, rule.condition) + rule.affix.map {|x| [x]}).reverse
      match = AffixMatch.new(rule.flag, rule.flag2, rule.cross,
                             0, "".bytes, rule.affix.size, rule.stripping, rule.rawsrc)
      add_rule_imp(self, match, condition, 0)
    elsif suffix? && from_stem?
      condition = (parse_condition(@alphabet, rule.condition) + rule.stripping.map {|x| [x]}).reverse
      match = AffixMatch.new(rule.flag, rule.flag2, rule.cross,
                             0, "".bytes, rule.stripping.size, rule.affix, rule.rawsrc)
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
                                                 : File.read(aff_file))
    virtual_stem_flag_s = ""
    AffFlags.mode = AffFlags::UTF8
    # The first pass to count the number of flags
    affdata.each_line do |l|
      if l =~ /^(\s*)FLAG\s+(\S*)/
        unless $1.empty?
          STDERR.puts "! The FLAG option has suspicious indentation and this makes it inactive."
          next
        end
        case $2
          when "UTF-8" then AffFlags.mode = AffFlags::UTF8
          when "long"  then AffFlags.mode = AffFlags::LONG
          when "num"   then AffFlags.mode = AffFlags::NUM
          else
            STDERR.puts "! Unrecognized FLAG option «#{$2}»."
          end
      elsif l =~ /^([SP])FX\s+(\S+)\s+(\S+)\s+(\S+)\s+(\S+)\s*(.*)$/
        AffFlags.register_flag($2)
      elsif l =~ /^(\s*)NEEDAFFIX\s+(\S+)$/
        unless $1.empty?
          STDERR.puts "! The NEEDAFFIX option has suspicious indentation and this makes it inactive."
          next
        end
        AffFlags.register_flag(virtual_stem_flag_s = $2)
      end
    end

    # The second pass to do the rest
    @alphabet = Alphabet.new("-" + charlist)
    @prefixes_from_stem = Ruleset.new(@alphabet, RULESET_PREFIX + RULESET_FROM_STEM)
    @suffixes_from_stem = Ruleset.new(@alphabet, RULESET_SUFFIX + RULESET_FROM_STEM)
    @prefixes_to_stem   = Ruleset.new(@alphabet, RULESET_PREFIX + RULESET_TO_STEM)
    @suffixes_to_stem   = Ruleset.new(@alphabet, RULESET_SUFFIX + RULESET_TO_STEM)
    @fullstrip = false
    @virtual_stem_flag = AffFlags.need_hash? ? {0 => true}.clear : I64_0
    @virtual_stem_flag = virtual_stem_flag_s.to_aff_flags
    flag = ""
    cnt = 0
    crossproduct = false
    affdata.each_line do |l|
      if l =~ /^\s*TRY\s+(\S+)(.*)$/
        @alphabet.encode_word($1)
      elsif l =~ /^\s*WORDCHARS\s+(\S+)(.*)$/
        @alphabet.encode_word($1)
      elsif l =~ /^\s*BREAK\s+(\S+)(.*)$/
        @alphabet.encode_word($1)
      elsif l =~ /^(\s*)FULLSTRIP\s*(\s+.*)?$/
        raise "Malformed FULLSTRIP directive (indented).\n" unless $1 == ""
        @fullstrip = true
      elsif cnt == 0 && l =~ /^\s*([SP])FX\s+(\S+)\s+(\S+)\s+(\d+)\s*(.*)$/
        type = $1
        flag = $2
        case $3 when "Y" then crossproduct = true
                when "N" then crossproduct = false
        else
          STDERR.puts "! Hunspell interprets the cross product field «#{$3}» as N."
          crossproduct = false
        end
        cnt = $4.to_i
        @alphabet.finalized_size
      elsif l =~ /^\s*([SP])FX\s+(\S+)\s+(\S+)\s+(\S+)\s+(\S+)\s*(.*)$/
        type = $1
        unless flag == $2
          STDERR.puts "! Invalid rule (flag mismatch): #{l}"
          exit 1
        end
          if (cnt -= 1) < 0
          STDERR.puts "! Invalid rule (wrong counter): #{l}"
          exit 1
        end
        stripping = ($3 == "0" ? "" : $3)
        affix     = ($4 == "0" ? "" : $4)
        condition = ($5 == "." ? stripping : $5)

        # Check the condition field for sanity.
        # FIXME: it would be nice to escape regular expressions here
        unless (type == "S" && condition =~ /#{stripping}$/) ||
               (type == "P" && condition =~ /^#{stripping}/)
          STDERR.puts "! Suspicious rule (strange condition field): #{l}"
          begin
          if (type == "S" && stripping =~ /#{condition}$/) ||
             (type == "P" && stripping =~ /^#{condition}/)
            STDERR.puts "! ... the condition is effectively the same as the stripping field."
            condition = stripping
          elsif type == "S" && condition =~ /(.*)((\[[^\]\)\(\[]+\]|[^\[\]]){#{stripping.size}})$/
            condition_p1 = $1
            condition_p2 = $2
            if stripping =~ /#{condition_p2}$/
              STDERR.puts "! ... the condition is equivalent to «#{condition_p1}#{stripping}»."
              condition = condition_p1 + stripping
            else
              STDERR.puts "! ... the condition is inert."
              next
            end
          elsif type == "P" && condition =~ /^((\[[^\]\)\(\[]+\]|.){#{stripping.size}})(.*)/
            condition_p1 = $1
            condition_p2 = $3
            if stripping =~ /^#{condition_p1}/
              STDERR.puts "! ... the condition is equivalent to «#{stripping}#{condition_p2}»."
              condition = stripping + condition_p2
            else
              STDERR.puts "! ... the condition is inert."
              next
            end
          else raise "" end
          rescue
            STDERR.puts "! ... can't figure it out and give up."
            exit 1
          end
        end

        condition = (type == "S") ? condition.gsub(/#{stripping}$/, "") :
                                    condition.gsub(/^#{stripping}/, "")
        flag2 = (affix =~ /\/(\S+)$/) ? $1 : ""
        affix = affix.gsub(/\/\S+$/, "")
        affix = "" if affix == "0"
        rule = Rule.new(flag.to_aff_flags, flag2.to_aff_flags, crossproduct,
                        @alphabet.encode_word(stripping),
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
    @tmpbuf3 = "".bytes
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
      stem_field, flags_field = $~.captures
      word = @alphabet.encode_word((stem_field || "").strip)
      flags = (flags_field || "").to_aff_flags

      # The stem itself is a word, unless it's a virtual stem (NEEDAFFIX flag)
      yield @alphabet.decode_word(word) unless aff_flags_intersect?(flags, @virtual_stem_flag)

      # Handle single prefixes without considering any suffixes
      prefixes_from_stem.matched_rules(word) do |pfx|
        if aff_flags_intersect?(flags, pfx.flag) && tmpbuf_apply_prefix(word, pfx)
          yield @alphabet.decode_word(@tmpbuf)
        end
      end

      # Start processing all possible suffixes
      suffixes_from_stem.matched_rules(word) do |sfx|
        if aff_flags_intersect?(flags, sfx.flag) && tmpbuf_apply_suffix(word, sfx)
          # Handle single suffixes without considering any prefixes or additional suffixes.
          # The suffix itself may have the NEEDAFFIX flag attached to it, which means that
          # it's not a real word without a second suffix.
          yield @alphabet.decode_word(@tmpbuf) unless aff_flags_intersect?(sfx.flag2, @virtual_stem_flag)

          # Handle combinations of a single suffix and a single prefix
          prefixes_from_stem.matched_rules(@tmpbuf) do |pfx|
            next unless pfx.cross && sfx.cross
            if aff_flags_intersect?(flags, pfx.flag) && (@tmpbuf.size != pfx.remove_left || @fullstrip)
              @tmpbuf2.clear
              @tmpbuf2.concat(pfx.append_left)
              (pfx.remove_left ... @tmpbuf.size).each {|i| @tmpbuf2 << @tmpbuf[i] }
              yield @alphabet.decode_word(@tmpbuf2)
            end
          end

          # Handle combinations of two suffixes
          suffixes_from_stem.matched_rules(@tmpbuf) do |sfx2|
            if aff_flags_intersect?(sfx.flag2, sfx2.flag) && (@tmpbuf.size != sfx2.remove_right || @fullstrip)
              @tmpbuf3.clear
              (0 ... @tmpbuf.size - sfx2.remove_right).each {|i| @tmpbuf3 << @tmpbuf[i] }
              @tmpbuf3.concat(sfx2.append_right)
              yield @alphabet.decode_word(@tmpbuf3)

              # Handle a possible prefix on top of two suffixes
              prefixes_from_stem.matched_rules(@tmpbuf3) do |pfx|
                next unless pfx.cross && sfx.cross && sfx2.cross
                if (aff_flags_intersect?(flags, pfx.flag) || aff_flags_intersect?(sfx.flag2, pfx.flag)) && (@tmpbuf3.size != pfx.remove_left || @fullstrip)
                  @tmpbuf2.clear
                  @tmpbuf2.concat(pfx.append_left)
                  (pfx.remove_left ... @tmpbuf3.size).each {|i| @tmpbuf2 << @tmpbuf3[i] }
                  yield @alphabet.decode_word(@tmpbuf2)
                end
              end
            end
          end
        end
      end
    end
  end
end

###############################################################################

def try_convert_dic_to_txt(alphabet, aff_file, dic_file, delimiter = nil, out_file = nil)
  aff = AFF.new(aff_file, alphabet)
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

def convert_dic_to_txt(aff_file, dic_file, delimiter = nil, out_file = nil)
  begin
    try_convert_dic_to_txt("", aff_file, dic_file, delimiter, out_file)
  rescue AlphabetException
    STDERR.puts "! Please ensure that the whole alphabet is accounted for in the TRY directive."
    a1 = alphabet_from_file(aff_file)
    a2 = alphabet_from_file(dic_file)
    try_convert_dic_to_txt(a1 + a2, aff_file, dic_file, delimiter, out_file)
  end
end

###############################################################################

class WordData
  def initialize(encword = "".bytes)
    @encword  = encword
    @flags    = AffFlags.need_hash? ? {0 => true}.clear : I64_0
    @covers   = [0].to_set.clear
  end

  def encword             ; @encword end
  def flags               ; @flags end
  def covers              ; @covers end
  def flags_merge(flags)  ; @flags = aff_flags_merge!(@flags, flags) end
  def flags_delete(flags) ; @flags = aff_flags_delete!(@flags, flags) end
end

###############################################################################

def try_convert_txt_to_dic(alphabet, aff_file, txt_file, out_file = nil)
  aff = AFF.new(aff_file, alphabet)

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
        idx_to_data[stem_idx].flags_merge(sfx.flag)
      elsif !aff_flags_empty?(aff.virtual_stem_flag)
        tmpbuf2 = tmpbuf.dup
        stem_idx = idx_to_data.size
        encword_to_idx[tmpbuf2] = idx_to_data.size
        data = WordData.new(tmpbuf2)
        data.flags_merge(sfx.flag)
        idx_to_data.push(data)
      end
    end
  end

  # Going from stems to the affixed words that they produce, identify and
  # remove all invalid flags
  idx_to_data.each_with_index do |data, idx|
    next if aff_flags_empty?(data.flags)
    encstem = data.encword
    aff.suffixes_from_stem.matched_rules(encstem) do |sfx|
      next if encstem.size == sfx.remove_right && !aff.fullstrip?
      next unless aff_flags_intersect?(data.flags, sfx.flag)

      tmpbuf.clear
      (0 ... encstem.size - sfx.remove_right).each {|i| tmpbuf << encstem[i] }
      tmpbuf.concat(sfx.append_right)

      if encword_to_idx.fetch(tmpbuf, virtual_stem_area_begin) >= virtual_stem_area_begin
        data.flags_delete(sfx.flag)
      end
    end
  end

  # Now that all flags are valid, retrive the full list of words that can
  # be generated from this stem
  idx_to_data.each_with_index do |data, idx|
    next if aff_flags_empty?(data.flags)
    encstem = data.encword

    data.covers.add(idx) unless idx >= virtual_stem_area_begin

    aff.suffixes_from_stem.matched_rules(encstem) do |sfx|
      next if encstem.size == sfx.remove_right && !aff.fullstrip?
      next unless aff_flags_intersect?(data.flags, sfx.flag)

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
        "/" + aff_flags_to_s(data.flags) + (stem_is_virtual ?
              aff_flags_to_s(aff.virtual_stem_flag) : "")] = true
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

def convert_txt_to_dic(aff_file, txt_file, out_file = nil)
  begin
    try_convert_txt_to_dic("", aff_file, txt_file, out_file)
  rescue AlphabetException
    STDERR.puts "! Please ensure that the whole alphabet is accounted for in the TRY directive."
    a1 = alphabet_from_file(aff_file)
    a2 = alphabet_from_file(txt_file)
    try_convert_txt_to_dic(a1 + a2, aff_file, txt_file, out_file)
  end
end

###############################################################################
# Tests for various tricky cases
###############################################################################

def test_dic_to_txt(affdata, input, expected_output)
  affdata = affdata.split('\n').map {|l| l.gsub(/^\s*(.*)?\s*$/, "\\1") }
                               .join('\n')
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

  # Long flags with two characters
  test_dic_to_txt("FLAG long
                   PFX Aa Y 1
                   PFX Aa ааа ба ааа
                   SFX Bb Y 1
                   SFX Bb ааа ав ааа", "ааааа/AaBb",
                   ["ааааа", "ааав", "бааа", "бав"])

  # Numeric flags
  test_dic_to_txt("FLAG num
                   PFX 1 Y 1
                   PFX 1 ааа ба ааа
                   SFX 2 Y 1
                   SFX 2 ааа ав ааа", "ааааа/1,2",
                   ["ааааа", "ааав", "бааа", "бав"])

  # Two levels of suffixes
  test_dic_to_txt("SET UTF-8
                   FULLSTRIP
                   NEEDAFFIX z
                   PFX A Y 2
                   PFX A лыжка сьвіньня лыжка
                   PFX A лыж шчот лыж
                   SFX B Y 1
                   SFX B екар ыжка лекар
                   SFX C Y 1
                   SFX C ка 0/ABz ка
                   PFX X Y 1
                   PFX X аая бю ааяр
                   SFX Y Y 1
                   SFX Y ааа яв/Z ааа
                   SFX Z Y 1
                   SFX Z в ргер в", "ааааа/XY",
                   ["ааааа", "ааяв", "ааяргер", "бюргер"])

  test_dic_to_txt("SET UTF-8
                   FULLSTRIP
                   NEEDAFFIX z
                   PFX A Y 2
                   PFX A лыжка сьвіньня лыжка
                   PFX A лыж шчот лыж
                   SFX B Y 1
                   SFX B екар ыжка лекар
                   SFX C Y 1
                   SFX C ка 0/ABz ка
                   PFX X Y 1
                   PFX X аая бю ааяр
                   SFX Y Y 1
                   SFX Y ааа яв/Z ааа
                   SFX Z Y 1
                   SFX Z в ргер в", "лекарка/C",
                   ["лекарка", "лыжка", "сьвіньня", "шчотка"])
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

unless args.size >= 1 && args[0] =~ /\.aff$/i
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
