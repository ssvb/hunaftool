#!/usr/bin/env ruby
# Copyright © 2025 Siarhei Siamashka
# SPDX-License-Identifier: CC-BY-SA-3.0+ OR MIT
#
# hunaftool - automated conversion between plain text word lists
#             and .DIC files for Hunspell, tailoring them for some
#             already existing .AFF file.

VERSION = 0.9

###############################################################################

require "set"
require "benchmark"

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

# Monkey-patch Ruby to make it recognize the Crystal's .to_i128 method
class Integer def to_i128() to_i end end

# An 8-bit zero constant to hint the use of UInt8 instead of Int32 for Crystal
U8_0 = "\0".bytes.first

# A 64-bit zero constant to hint the use of Int64 instead of Int32 for Crystal
I64_0 = (0x3FFFFFFFFFFFFFFF & 0)

# A 128-bit zero constant to hint the use of Int128 instead of Int32 for Crystal
I128_0 = 0.to_i128

# This is a Ruby-compatible trick to create a Crystal's lightweight tuple
def tuple2(a, b) return a, b end

###############################################################################

module Cfg
  @@verbose = false
  @@prune_aff = false
  def self.verbose?      ; @@verbose end
  def self.verbose=(v)   ; @@verbose = v end
  def self.prune_aff?    ; @@prune_aff end
  def self.prune_aff=(v) ; @@prune_aff = v end
end

# Run a subtask with optional reporting about performance and memory usage
def subtask(caption)
  unless Cfg.verbose?
    yield
    return
  end
  if COMPILED_BY_CRYSTAL
    total_bytes = GC.stats.total_bytes
    t = Benchmark.measure { yield }
    GC.collect
    footprint = GC.stats.heap_size - GC.stats.free_bytes
    alloc_bw = GC.stats.total_bytes - total_bytes
    STDERR.printf("== %s (time: +%.2fs, alloc: ±%.0fMB, total: %.0fMB)\n",
                  caption, t.real, alloc_bw.to_f / 1000000,
                  footprint.to_f / 1000000)
  else
    t = Benchmark.measure { yield }
    STDERR.printf("== %s (time: +%.2fs)\n", caption, t.real)
  end
  nil
end

###############################################################################
# Remap UTF-8 words to indexable 8-bit arrays for performance reasons. All
# characters of the alphabet are consecutively numbered starting from 0 with
# no gaps or holes. This allows to have much faster array lookups instead
# of hash lookups when navigating a https://en.wikipedia.org/wiki/Trie
# data structure.
###############################################################################

class AlphabetException < Exception
end

module Alphabet
  @@char_to_idx   = {'a' => U8_0}.clear
  @@idx_to_char   = ['a'].clear
  @@idx_to_weight = [[0, 0, 0]].clear
  @@finalized     = false

  def self.reset(characters)
    @@char_to_idx = {'a' => U8_0}.clear
    @@idx_to_char = ['a'].clear
    @@idx_to_weight = [[0, 0, 0]].clear
    @@finalized   = false
    characters.to_8bit
  end

  def self.finalized_size
    @@finalized = true
    @@idx_to_char.size
  end

  def self.idx_to_char   ; @@idx_to_char end
  def self.idx_to_weight ; @@idx_to_weight end
  def self.char_to_idx   ; @@char_to_idx end
  def self.finalized     ; @@finalized   end

  # Since Ruby doesn't support the Unicode Collation Algorithm (UCA) out of the box,
  # this is a simplified partial placeholder implementation, which only focuses on
  # the European languages rather than trying to handle everything. The list of
  # characters relevant for the European languages had been taken from
  #     https://www.open-std.org/cen/tc304/EOR/eor4r_tab.txt
  # Then these characters were found in https://www.unicode.org/Public/UCA/16.0.0/allkeys.txt
  # and presented here as strings. The L2 weights are all identical for these characters
  # in DUCET, so processing of L2 is skipped entirely here.
  @@euroducet_base =
    "¤¢$£¥₣₤€₯0123456789abcdeəfƒgǥhʻʽiıjklmnŋopqĸrɼstŧuvwxyzʒþʼˮαβγδεϝϛζηθικλμνξοπϟρσ" +
    "τυφχψωϡаәӕбвгғҕдђҙеєжҗзѕӡиійјкқӄҡҟҝлљмнңӈҥњоөпҧрсҫтҭћуүұфхҳһцҵчҷӌҹҽҿџшщъыьэюяҩӀ"
  @@euroducet_all =
    "¤¢$£¥₣₤€₯01¹½¼⅛2²₂3³¾⅜45⅝67⅞89aAªáÁàÀăĂâÂåÅǻǺäÄǟǞãÃǡǠąĄāĀæÆǽǼǣǢbBḃḂcCćĆĉĈčČċĊçÇ℅" +
    "dDďĎḋḊđĐðÐeEéÉèÈĕĔêÊěĚëËėĖęĘēĒəƏfFḟḞﬁﬂƒgGğĞĝĜǧǦġĠģĢǥǤhHĥĤȟȞħĦʻʽiIíÍìÌĭĬîÎïÏĩĨİįĮ" +
    "īĪĳĲıjJĵĴkKǩǨķĶlLĺĹľĽļĻłŁŀĿmMṁṀnNⁿńŃňŇñÑņŅ№ŋŊoOºóÓòÒŏŎôÔöÖőŐõÕøØǿǾǫǪǭǬōŌœŒpPṗṖ₧q" +
    "QĸrRŕŔřŘŗŖɼsSśŚŝŜšŠṡṠşŞșȘſẛßtTťŤṫṪţŢțȚ™ŧŦuUúÚùÙŭŬûÛůŮüÜűŰũŨųŲūŪvVwWẃẂẁẀŵŴẅẄxXyYý" +
    "ÝỳỲŷŶÿŸzZźŹžŽżŻʒƷǯǮþÞʼŉˮαΑἀἈἄἌᾄᾌἂἊᾂᾊἆἎᾆᾎᾀᾈἁἉἅἍᾅᾍἃἋᾃᾋἇἏᾇᾏᾁᾉάάΆΆᾴὰᾺᾲᾰᾸᾶᾷᾱᾹᾳᾼβϐΒγΓδ" +
    "ΔεΕἐἘἔἜἒἚἑἙἕἝἓἛέέΈΈὲῈϝϜϛϚζΖηΗἠἨἤἬᾔᾜἢἪᾒᾚἦἮᾖᾞᾐᾘἡἩἥἭᾕᾝἣἫᾓᾛἧἯᾗᾟᾑᾙήήΉΉῄὴῊῂῆῇῃῌθϑΘιιΙἰ" +
    "ἸἴἼἲἺἶἾἱἹἵἽἳἻἷἿίίΊΊὶῚῐῘῖϊΪΐΐῒῗῑῙκϰΚϗλΛμµΜνΝξΞοΟὀὈὄὌὂὊὁὉὅὍὃὋόόΌΌὸῸπϖΠϟϞρϱΡῤῥῬσΣςτ" +
    "ΤυΥὐὔὒὖὑὙὕὝὓὛὗὟύύΎΎὺῪῠῨῦϋΫΰΰῢῧῡῩφϕΦχΧψΨωΩΩὠὨὤὬᾤᾬὢὪᾢᾪὦὮᾦᾮᾠᾨὡὩὥὭᾥᾭὣὫᾣᾫὧὯᾧᾯᾡᾩώώΏΏῴὼ" +
    "ῺῲῶῷῳῼϡϠаАӑӐӓӒәӘӛӚӕӔбБвВгГѓЃґҐғҒҕҔдДђЂҙҘеЕѐЀӗӖёЁєЄжЖӂӁӝӜҗҖзЗӟӞѕЅӡӠиИѝЍӥӤӣӢіІїЇйЙ" +
    "јЈкКќЌқҚӄӃҡҠҟҞҝҜлЛљЉмМнНңҢӈӇҥҤњЊоОӧӦөӨӫӪпПҧҦрРсСҫҪтТҭҬћЋуУўЎӱӰӳӲӯӮүҮұҰфФхХҳҲһҺцЦ" +
    "ҵҴчЧӵӴҷҶӌӋҹҸҽҼҿҾџЏшШщЩъЪыЫӹӸьЬэЭюЮяЯҩҨӀ"
  @@euroducet_skippable =
    "	 !\"#%&'()*+,-./:;<=>?@[\]^_`{|}~ ¡¦§¨©«®¯°±´¶·¸»¿×÷ʹʺ˂˃˄˅‐‑‒–—―‖‗‘’‚‛“”„‟†‡•" +
    "‣․‥…‰→∞≈≠≡≤≥♯"
  l1_weights = {'a' => 0}.clear
  @@euroducet_base.chars.each_with_index {|ch, idx| l1_weights[ch] = idx }
  @@euroducet_weights = {'a' => [0, 0, 0]}.clear
  l1_idx = 0
  @@euroducet_all.chars.each_with_index {|ch, l3_idx| @@euroducet_weights[ch] =
                    [1 + (l1_idx = l1_weights.fetch(ch, l1_idx)), 1 + l3_idx, ch.ord] }
  def self.collation_weight(ch)
    @@euroducet_skippable.index(ch) ? [-1, -1, ch.ord] : @@euroducet_weights.fetch(ch,
      ((ch.ord < 128) ? [0, 0, ch.ord] : [0x7FFFFFFF, 0x7FFFFFFF, ch.ord]))
  end
end

class String
  def to_8bit
    out = "".bytes
    self.each_char do |ch|
      unless Alphabet.char_to_idx.has_key?(ch)
        if Alphabet.finalized
          STDERR.puts "! An unexpected character «#{ch}» encountered while processing «#{self}»."
          raise AlphabetException.new
        end
        Alphabet.char_to_idx[ch] = U8_0 + Alphabet.idx_to_char.size
        Alphabet.idx_to_char   << ch
        Alphabet.idx_to_weight << Alphabet.collation_weight(ch)
      end
      out << Alphabet.char_to_idx[ch]
    end
    out
  end
end

class Array
  def to_utf8
    self.map {|idx| Alphabet.idx_to_char[idx] }.join
  end

  # Interpret two arrays as 8-bit-remapped Unicode strings and compare them using
  # the rules, which partially implement the Unicode Collation Algorithm (UCA)
  # from http://www.unicode.org/reports/tr10/
  def collate(other, level = 0)
    i, j = 0, 0
    while true
      w1, w2 = -1, -1
      # Handle skipping of the punctuation characters if necessary at this level.
      while i < self.size && ((w1 = Alphabet.idx_to_weight[self[i]][level]) == -1)
        i += 1
      end
      while j < other.size && ((w2 = Alphabet.idx_to_weight[other[j]][level]) == -1)
        j += 1
      end
      # No more data and still undecided? Try the next level or end the comparison.
      return ((level == 2) ? 0 : collate(other, level + 1)) if w1 == -1 && w2 == -1
      # Compare the current character.
      return -1 if w1 < w2
      return 1 if w1 > w2
      i += 1
      j += 1
    end
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

  SWITCH_TO_HASH_THRESHOLD  = (COMPILED_BY_CRYSTAL ? 128 : 62)

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
  def self.need_hash? ; @@bitpos_to_flagname.size > SWITCH_TO_HASH_THRESHOLD end

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
      tmp = I128_0
      case AffFlags.mode when AffFlags::LONG
        STDERR.puts "! The flags field «#{self}» must have an even number of characters." if size.odd?
        self.scan(/(..)/) { tmp |= ((I128_0 + 1) << AffFlags.flagname_to_bitpos($1, self)) }
      when AffFlags::NUM then
        unless self.strip.empty?
          self.split(',').each {|chunk| tmp |= ((I128_0 + 1) << AffFlags.flagname_to_bitpos(chunk.strip, self)) }
        end
      else
        self.each_char {|ch| tmp |= ((I128_0 + 1) << AffFlags.flagname_to_bitpos(ch, self)) }
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
      .each_index.select {|idx| (((I128_0 + 1) << idx) & flags) != 0 }
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

def parse_condition(condition)
  out = ["".bytes].clear
  condition.scan(/\[\^([^\]]*)\]|\[([^\]\^]*)\]|(.)/) do
    m1, m2, m3 = $~.captures
    out << if m1
      tmp = {0 => true}.clear
      m1.to_8bit.each {|idx| tmp[idx] = true }
      Alphabet.finalized_size.times.map {|x| U8_0 + x }.select {|idx| !tmp.has_key?(idx) }.to_a
    elsif m2
      m2.to_8bit.sort.uniq
    else
      m3.to_s.to_8bit
    end
  end
  out
end

# That's an affix rule, pretty much in the same format as in .AFF files
class Rule
  def initialize(flag = I128_0, flag2 = I128_0, crossproduct = true,
                 stripping = "".bytes, affix = "".bytes, condition = "", rawsrc = "", tags = "")
    @flag = {0 => true}.clear if AffFlags.need_hash?
    @flag2 = {0 => true}.clear if AffFlags.need_hash?
    @flag, @flag2, @crossproduct, @stripping, @affix, @condition, @rawsrc, @tags =
      flag, flag2, crossproduct, stripping, affix, condition, rawsrc, tags
  end
  def flag       ; @flag      end
  def flag2      ; @flag2     end
  def cross      ; @crossproduct end
  def stripping  ; @stripping end
  def affix      ; @affix     end
  def condition  ; @condition end
  def rawsrc     ; @rawsrc    end
  def tags       ; @tags      end
end

# That's a processed result of matching a rule. It may be adjusted
# depending on what is the desired result.
class AffixMatch
  def initialize(flag = I128_0, flag2 = I128_0, crossproduct = true,
                 remove_left = 0, append_left = "".bytes, remove_right = 0, append_right = "".bytes,
                 rawsrc = "", tags = "")
    @flag = {0 => true}.clear if AffFlags.need_hash?
    @flag2 = {0 => true}.clear if AffFlags.need_hash?
    @flag, @flag2, @crossproduct, @remove_left, @append_left, @remove_right, @append_right, @rawsrc, @tags =
      flag, flag2, crossproduct, remove_left, append_left, remove_right, append_right, rawsrc, tags
  end
  def flag         ; @flag               end
  def flag2        ; @flag2              end
  def cross        ; @crossproduct       end
  def remove_left  ; @remove_left        end
  def append_left  ; @append_left        end
  def remove_right ; @remove_right       end
  def append_right ; @append_right       end
  def rawsrc       ; @rawsrc    end
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
  def initialize(opts = 0)
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
        trie_node.children = [nil] * Alphabet.finalized_size + [self] if children.empty?
        return unless children = trie_node.children
        children[ch_idx] = Ruleset.new unless children[ch_idx]
        add_rule_imp(children[ch_idx], rule, condition, condition_idx + 1)
      end
    end
  end

  def add_rule(rule)
    if prefix? && to_stem?
      condition = rule.affix.map {|x| [x]} + parse_condition(rule.condition)
      match = AffixMatch.new(rule.flag, rule.flag2, rule.cross,
                             rule.affix.size, rule.stripping, 0, "".bytes, rule.rawsrc, rule.tags)
      add_rule_imp(self, match, condition, 0)
    elsif prefix? && from_stem?
      condition = rule.stripping.map {|x| [x]} + parse_condition(rule.condition)
      match = AffixMatch.new(rule.flag, rule.flag2, rule.cross,
                             rule.stripping.size, rule.affix, 0, "".bytes, rule.rawsrc, rule.tags)
      add_rule_imp(self, match, condition, 0)
    elsif suffix? && to_stem?
      condition = (parse_condition(rule.condition) + rule.affix.map {|x| [x]}).reverse
      match = AffixMatch.new(rule.flag, rule.flag2, rule.cross,
                             0, "".bytes, rule.affix.size, rule.stripping, rule.rawsrc, rule.tags)
      add_rule_imp(self, match, condition, 0)
    elsif suffix? && from_stem?
      condition = (parse_condition(rule.condition) + rule.stripping.map {|x| [x]}).reverse
      match = AffixMatch.new(rule.flag, rule.flag2, rule.cross,
                             0, "".bytes, rule.stripping.size, rule.affix, rule.rawsrc, rule.tags)
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
    @affdata = (((opt & RULESET_TESTSTRING) != 0) ? aff_file
                                                  : File.read(aff_file))
    virtual_stem_flag_s = ""
    forbiddenword_flag_s = ""
    AffFlags.mode = AffFlags::UTF8
    # The first pass to count the number of flags
    @affdata.each_line do |l|
      if l =~ /^(\s*)FLAG\s+(\S*)/
        unless $1.empty?
          STDERR.puts "! The FLAG option is indented and this makes it inactive."
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
      elsif l =~ /^(\s*)(NEEDAFFIX|FORBIDDENWORD)\s+(\S+)$/
        unless $1.empty?
          STDERR.puts "! The NEEDAFFIX option is indented and this makes it inactive."
          next
        end
        case $2
          when "NEEDAFFIX" then AffFlags.register_flag(virtual_stem_flag_s = $3)
          when "FORBIDDENWORD" then AffFlags.register_flag(forbiddenword_flag_s = $3)
        end
      end
    end

    # The second pass to do the rest
    Alphabet.reset(" " + charlist)
    @prefixes_from_stem = Ruleset.new(RULESET_PREFIX + RULESET_FROM_STEM)
    @suffixes_from_stem = Ruleset.new(RULESET_SUFFIX + RULESET_FROM_STEM)
    @prefixes_to_stem   = Ruleset.new(RULESET_PREFIX + RULESET_TO_STEM)
    @suffixes_to_stem   = Ruleset.new(RULESET_SUFFIX + RULESET_TO_STEM)
    @fullstrip = false
    @virtual_stem_flag  = AffFlags.need_hash? ? {0 => true}.clear : I128_0
    @virtual_stem_flag  = virtual_stem_flag_s.to_aff_flags
    @forbiddenword_flag = AffFlags.need_hash? ? {0 => true}.clear : I128_0
    @forbiddenword_flag = forbiddenword_flag_s.to_aff_flags
    flag = ""
    cnt = 0
    crossproduct = false
    @affdata.each_line do |l|
      if l =~ /^\s*TRY\s+(\S+)(.*)$/
        $1.to_8bit
      elsif l =~ /^\s*WORDCHARS\s+(\S+)(.*)$/
        $1.to_8bit
      elsif l =~ /^\s*BREAK\s+(\S+)(.*)$/
        $1.to_8bit
      elsif l =~ /^(\s*)FULLSTRIP\s*(\s+.*)?$/
        unless $1.empty?
          STDERR.puts "! The FULLSTRIP option is indented and this makes it inactive."
          next
        end
        @fullstrip = true
      elsif cnt == 0 && l =~ /^\s*([SP])FX\s+(\S+)\s+(\S+)\s+(\d+)(\s|$)/
        type = $1
        flag = $2
        case $3 when "Y" then crossproduct = true
                when "N" then crossproduct = false
        else
          STDERR.puts "! Hunspell interprets the cross product field «#{$3}» as N."
          crossproduct = false
        end
        cnt = $4.to_i
        Alphabet.finalized_size
      elsif l =~ /^\s*([SP])FX\s+(\S+)\s+(\S+)\s+(\S+)\s*(\S*)\s*([^#]*)/
        type = $1
        unless flag == $2
          STDERR.puts "! Fatal error. Invalid rule (flag mismatch): «#{l.strip}»"
          exit 1
        end
        if (cnt -= 1) < 0
          STDERR.puts "! Fatal error. Invalid rule (wrong counter): «#{l.strip}»"
          exit 1
        end
        stripping = ($3 == "0" ? "" : $3)
        affix     = ($4 == "0" ? "" : $4)
        condition = (($5 != "" && $5 != ".") ? $5 : stripping)
        tags      = $6.strip
        if $5 == ""
          STDERR.puts "! No condition field in «#{l.strip}», default to «.» or «#{stripping}»"
        end

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
              STDERR.puts "! ... the condition is inactive."
              next
            end
          elsif type == "P" && condition =~ /^((\[[^\]\)\(\[]+\]|.){#{stripping.size}})(.*)/
            condition_p1 = $1
            condition_p2 = $3
            if stripping =~ /^#{condition_p1}/
              STDERR.puts "! ... the condition is equivalent to «#{stripping}#{condition_p2}»."
              condition = stripping + condition_p2
            else
              STDERR.puts "! ... the condition is inactive."
              next
            end
          else raise "" end
          rescue
            STDERR.puts "! ... can't figure it out."
            next
          end
        end

        condition = (type == "S") ? condition.gsub(/#{stripping}$/, "") :
                                    condition.gsub(/^#{stripping}/, "")
        flag2 = (affix =~ /\/(\S+)$/) ? $1 : ""
        affix = affix.gsub(/\/\S+$/, "")
        affix = "" if affix == "0"
        rule = Rule.new(flag.to_aff_flags, flag2.to_aff_flags, crossproduct,
                        stripping.to_8bit, affix.to_8bit, condition, l.strip, tags)
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

  def prefixes_from_stem ; @prefixes_from_stem end
  def suffixes_from_stem ; @suffixes_from_stem end
  def prefixes_to_stem   ; @prefixes_to_stem end
  def suffixes_to_stem   ; @suffixes_to_stem end
  def fullstrip?         ; @fullstrip end
  def virtual_stem_flag  ; @virtual_stem_flag end
  def forbiddenword_flag ; @forbiddenword_flag end

  @@useful_rules = {"" => 0}.clear

  def mark_useful_rule(rule)
    @@useful_rules[rule.rawsrc] = @@useful_rules.fetch(rule.rawsrc, 0) + 1
  end

  # Return the optimized AFF file with unnecessary rules removed from it
  def aff_data_with_pruned_rules
    curflag = ""
    curflagcnt = 0
    flaglineno = -1
    lines = [""].clear
    @affdata.each_line do |l|
      l = l.strip
      if l =~ /^[SP]FX\s+(\S+)\s+(\S+)\s+(\S+)/
        if curflag != $1
          curflag = $1
          if flaglineno != -1
            lines[flaglineno] = (curflagcnt == 0) ? "" :
              lines[flaglineno].sub(/^([SP]FX\s+(\S+)\s+(\S+)\s+)(\S+)/, "\\1#{curflagcnt}")
          end
          flaglineno = lines.size
          curflagcnt = 0
          lines.push(l)
        end
        if @@useful_rules.has_key?(l)
          lines.push(l)
          curflagcnt += 1
        end
      else
        lines.push(l)
      end
    end
    if flaglineno != -1
      lines[flaglineno] = (curflagcnt == 0) ? "" :
        lines[flaglineno].sub(/^([SP]FX\s+(\S+)\s+(\S+)\s+)(\S+)/, "\\1#{curflagcnt}")
    end
    lines.join("\n")
  end

  # Find all wordforms produced by a stem with a specified set of flags.
  # Each of the matched wordforms is yielded to a block along with the
  # prefix flags and the suffix flags that triggered this match.
  #
  # Note: the yilded wordform is in 8-bit encoding and it references to
  #       the internal temporary buffer, which is going to be overwritten!
  #       If this wordform needs to be stored somewhere, then a copy needs
  #       to be allocated via the .dup method.
  def expand_stem(stem, flags)
    # The FORBIDDENWORD flag applies to all wordforms generated from this stem
    forbidden = aff_flags_intersect?(flags, @forbiddenword_flag)

    # The stem itself is a wordform too (unless it's a virtual stem
    # specifically labelled by the NEEDAFFIX flag).
    yield stem, nil, nil, forbidden unless aff_flags_intersect?(flags, @virtual_stem_flag)

    # Iterate over all single prefixes.
    prefixes_from_stem.matched_rules(stem) do |pfx|
      # Check if we have a match for the necessary affix flags.
      if aff_flags_intersect?(flags, pfx.flag) && (stem.size != pfx.remove_left || @fullstrip)
        mark_useful_rule(pfx) if Cfg.prune_aff?
        # Apply the current prefix.
        @tmpbuf.clear
        @tmpbuf.concat(pfx.append_left)
        (pfx.remove_left ... stem.size).each {|i| @tmpbuf << stem[i] }
        # Yield a wordform constructed from the current single prefix.
        yield @tmpbuf, pfx.flag, nil, forbidden
      end
    end

    # Iterate over all first level suffixes.
    suffixes_from_stem.matched_rules(stem) do |sfx|
      # Check if we have a match for the necessary affix flags.
      if aff_flags_intersect?(flags, sfx.flag) &&
                                        (stem.size != sfx.remove_right || @fullstrip)
        mark_useful_rule(sfx) if Cfg.prune_aff?
        # One more opportunity to activate the FORBIDDENWORD flag is here
        forbidden2 = forbidden || aff_flags_intersect?(sfx.flag2, @forbiddenword_flag)
        # Apply the current first level suffix.
        @tmpbuf.clear
        (0 ... stem.size - sfx.remove_right).each {|i| @tmpbuf << stem[i] }
        @tmpbuf.concat(sfx.append_right)
        # Yield a wordform constructed from the current single suffix. But this suffix may
        # have the NEEDAFFIX flag attached to it, which would means that it's not a real
        # wordform (the second level suffix is necessary).
        yield @tmpbuf, nil, sfx.flag, forbidden2 unless aff_flags_intersect?(sfx.flag2, @virtual_stem_flag)

        unless aff_flags_empty?(sfx.flag2)
          # Iterate over all second level suffixes.
          suffixes_from_stem.matched_rules(@tmpbuf) do |sfx2|
            # Check if we have a match for the necessary affix flags.
            if aff_flags_intersect?(sfx.flag2, sfx2.flag) &&
                                          (@tmpbuf.size != sfx2.remove_right || @fullstrip)
              mark_useful_rule(sfx2) if Cfg.prune_aff?
              # Apply the current second level suffix on top of the first level suffix.
              @tmpbuf3.clear
              (0 ... @tmpbuf.size - sfx2.remove_right).each {|i| @tmpbuf3 << @tmpbuf[i] }
              @tmpbuf3.concat(sfx2.append_right)
              # Yield a wordform constructed from two suffixes.
              yield @tmpbuf3, nil, sfx.flag, forbidden2

              # If no cross product support on the suffix side, then we are done
              next unless sfx.cross && sfx2.cross

              # Iterate over prefixes after having two suffixes already applied.
              prefixes_from_stem.matched_rules(@tmpbuf3) do |pfx|
                # Check the crossproduct flags to confirm that this prefix can be applied.
                next unless pfx.cross
                # Check if we have a match for the necessary affix flags.
                direct_pfx_match = aff_flags_intersect?(flags, pfx.flag)
                sfx_induced_pfx_match = aff_flags_intersect?(sfx.flag2, pfx.flag)
                if (direct_pfx_match || sfx_induced_pfx_match) &&
                                          (@tmpbuf3.size != pfx.remove_left || @fullstrip)
                  mark_useful_rule(pfx) if Cfg.prune_aff?
                  # Apply the current prefix on top of the two already applied suffixes.
                  @tmpbuf2.clear
                  @tmpbuf2.concat(pfx.append_left)
                  (pfx.remove_left ... @tmpbuf3.size).each {|i| @tmpbuf2 << @tmpbuf3[i] }
                  # Yield a wordform constructed from two suffixes and one prefix.
                  yield @tmpbuf2, pfx.flag, sfx.flag, forbidden2 if direct_pfx_match
                  yield @tmpbuf2, sfx.flag, sfx.flag, forbidden2 if sfx_induced_pfx_match
                end
              end
            end
          end
        end

        # If no cross product support on the suffix side, then we are done
        next unless sfx.cross

        # Iterate over prefixes after having one suffix already applied.
        prefixes_from_stem.matched_rules(@tmpbuf) do |pfx|
          # Check the crossproduct flags to confirm that this prefix can be applied.
          next unless pfx.cross
          # Check if we have a match for the necessary affix flags.
          direct_pfx_match = aff_flags_intersect?(flags, pfx.flag)
          sfx_induced_pfx_match = aff_flags_intersect?(sfx.flag2, pfx.flag)
          if (direct_pfx_match || sfx_induced_pfx_match) &&
                                        (@tmpbuf.size != pfx.remove_left || @fullstrip)
            mark_useful_rule(pfx) if Cfg.prune_aff?
            # Apply the current prefix on top of a single first level suffix.
            @tmpbuf2.clear
            @tmpbuf2.concat(pfx.append_left)
            (pfx.remove_left ... @tmpbuf.size).each {|i| @tmpbuf2 << @tmpbuf[i] }
            # Yield a wordform constructed from one suffix and one prefix.
            yield @tmpbuf2, pfx.flag, sfx.flag, forbidden if direct_pfx_match
            yield @tmpbuf2, sfx.flag, sfx.flag, forbidden if sfx_induced_pfx_match
          end
        end
      end
    end
  end

  def decode_dic_entry(line)
    stem = ""
    if line =~ /^([^\/]+)\/?(\S*)/
      expand_stem($1.strip.to_8bit, $2.to_aff_flags) do |wordform, pfx_flag, sfx_flag, forbidden|
        wordform_utf8 = wordform.to_utf8
        stem = wordform_utf8 if !pfx_flag && !sfx_flag
        yield wordform_utf8, forbidden
      end
    end
    stem
  end

  # This is the opposite of "expand_stem". Given a wordform, this function probes
  # all possible stems that can potentially generate this wordform and yields
  # this information to the caller.
  #
  # Note: the yilded stem is in 8-bit encoding and it references to
  #       the internal temporary buffer, which is going to be overwritten!
  #       If this wordform needs to be stored somewhere, then a copy needs
  #       to be allocated via the .dup method.
  def lookup_stem(wordform)
    suffixes_to_stem.matched_rules(wordform) do |sfx|
      next if wordform.size == sfx.remove_right && !fullstrip? # FULLSTRIP compat
      # Strip the current suffix
      @tmpbuf.clear
      (0 ... wordform.size - sfx.remove_right).each {|i| @tmpbuf << wordform[i] }
      @tmpbuf.concat(sfx.append_right)
      # Yield the resulting stem candidate
      yield @tmpbuf, nil, sfx.flag

      # one more suffix on top of a suffix
      suffixes_to_stem.matched_rules(@tmpbuf) do |sfx2|
        next if @tmpbuf.size == sfx2.remove_right && !fullstrip? # FULLSTRIP compat
        # Check if this combination of suffixes is valid
        next unless aff_flags_intersect?(sfx2.flag2, sfx.flag)
        # Strip the current suffix after the stripped suffix
        @tmpbuf2.clear
        (0 ... @tmpbuf.size - sfx2.remove_right).each {|i| @tmpbuf2 << @tmpbuf[i] }
        @tmpbuf2.concat(sfx2.append_right)
        # Yield the resulting stem candidate
        yield @tmpbuf2, nil, sfx2.flag
      end
    end

    # a prefix
    prefixes_to_stem.matched_rules(wordform) do |pfx|
      next if wordform.size == pfx.remove_left && !fullstrip? # FULLSTRIP compat
      # Strip the current prefix
      @tmpbuf.clear
      @tmpbuf.concat(pfx.append_left)
      (pfx.remove_left ... wordform.size).each {|i| @tmpbuf << wordform[i] }
      # Yield the resulting stem candidate
      yield @tmpbuf, pfx.flag, nil

      # If no cross product support on the prefix side, then we are done
      next unless pfx.cross

      # a suffix on top of a prefix
      suffixes_to_stem.matched_rules(@tmpbuf) do |sfx|
        next if @tmpbuf.size == sfx.remove_right && !fullstrip? # FULLSTRIP compat
        # Check the crossproduct flags to confirm that this suffix can be stripped.
        next unless sfx.cross
        # Strip the current suffix after the stripped prefix
        @tmpbuf2.clear
        (0 ... @tmpbuf.size - sfx.remove_right).each {|i| @tmpbuf2 << @tmpbuf[i] }
        @tmpbuf2.concat(sfx.append_right)
        # Yield the resulting stem candidate
        yield @tmpbuf2, pfx.flag, sfx.flag

        # one more suffix on top of a suffix and a prefix
        suffixes_to_stem.matched_rules(@tmpbuf2) do |sfx2|
          next if @tmpbuf2.size == sfx2.remove_right && !fullstrip? # FULLSTRIP compat
          # Check the crossproduct flags to confirm that this suffix can be stripped.
          next unless sfx2.cross
          # Check if this combination of suffixes is valid
          next unless aff_flags_intersect?(sfx2.flag2, sfx.flag)
          # Strip the current suffix after the stripped suffix
          @tmpbuf3.clear
          (0 ... @tmpbuf2.size - sfx2.remove_right).each {|i| @tmpbuf3 << @tmpbuf2[i] }
          @tmpbuf3.concat(sfx2.append_right)
          # Yield the resulting stem candidate
          yield @tmpbuf3, pfx.flag, sfx2.flag
        end
      end
    end
  end
end

###############################################################################

def try_convert_dic_to_txt(alphabet, aff_file, dic_file, delimiter = nil, out_file = nil)
  aff = AFF.new(aff_file, alphabet)
  badlist       = {"" => true}.clear
  results       = [[""]].clear
  results_filt  = [[""]].clear
  stemwordlist  = {"" => true}.clear
  firstline     = true
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
        STDERR.puts "! Malformed .DIC file: the words counter is missing."
        alreadywarned = true
      end
    end
    if expected_number_of_stems != -1 &&
             real_number_of_stems > expected_number_of_stems && !alreadywarned
      STDERR.puts "! Malformed .DIC file: the words counter is too small."
      alreadywarned = true
    end
    if l.empty?
      STDERR.puts "! Malformed .DIC file: an unexpected empty line."
      alreadywarned = true
    else
      if delimiter
        stemwordlist.clear
        stem = aff.decode_dic_entry(l) do |word, forbidden|
          badlist[word] = true if forbidden
          stemwordlist[word] = true
        end
        unless stem.empty?
          results.push(stemwordlist.keys)
        else
          stemwordlist.each_key {|word| results.push([word]) }
        end
      else
        aff.decode_dic_entry(l) do |word, forbidden|
          badlist[word] = true if forbidden
          results.push([word])
        end
      end
      real_number_of_stems += 1
    end
  end

  # Filter out bad words
  results.each do |a|
    next if a.empty?
    stemword = a.first
    tmp = a.select {|word| !badlist.has_key?(word) }
    next if tmp.empty?
    if tmp.first == stemword
      results_filt.push(tmp)
    else
      tmp.each {|v| results_filt.push([v]) }
    end
  end

  # If we were requested to prune the unnecessary rules, then
  # this is what we do here instead of producing the wordlist
  if Cfg.prune_aff?
    if out_file
      File.write(out_file, aff.aff_data_with_pruned_rules)
    else
      puts aff.aff_data_with_pruned_rules
    end
    return
  end

  results = [""].clear
  if delimiter
    results_filt.each do |a|
      if a.size > 1
        stem = a.shift
        results.push(stem + delimiter + a.sort.join(delimiter))
      else
        results.push(a.join(delimiter))
      end
    end
    results = results.sort.uniq
  else
    results = results_filt.flatten.sort.uniq
  end

  if out_file
    fh = File.open(out_file, "w")
    results.each {|a| fh.puts a }
    fh.close
  else
    results.each {|a| puts a }
  end
end

def convert_dic_to_txt(aff_file, dic_file, delimiter = nil, out_file = nil)
  begin
    try_convert_dic_to_txt("", aff_file, dic_file, delimiter, out_file)
  rescue AlphabetException
    STDERR.puts "! The TRY directive should preferably cover the whole alphabet."
    a1 = alphabet_from_file(aff_file)
    a2 = alphabet_from_file(dic_file)
    try_convert_dic_to_txt(a1 + a2, aff_file, dic_file, delimiter, out_file)
  end
end

###############################################################################

class WordData
  def initialize(encword = "".bytes)
    @encword  = encword
    @flags    = AffFlags.need_hash? ? {0 => true}.clear : I128_0
    @covers   = [0].clear
  end

  def encword             ; @encword end
  def flags               ; @flags end
  def flags=(newflags)    ; @flags = newflags end
  def covers              ; @covers end
  def covers=(newcovers)  ; @covers = newcovers end
  def flags_merge(flags)  ; @flags = aff_flags_merge!(@flags, flags) end
  def flags_delete(flags) ; @flags = aff_flags_delete!(@flags, flags) end
end

###############################################################################
# This removes redundant flags. But the algorithm is not perfect.
# TODO: bruteforce the exact solution for the small sets of flags.
###############################################################################

def optimize_flags(aff, stem, flags, flag_freqs, flag_names)
  # Empty flags sample
  empty_flags = aff_flags_delete!(flags.dup, flags)
  # Empty flags is a special slot. It's needed just in case if there's zero
  # affix producing the stem itself (together with some flag). So we need
  # an empty flag to "compete" against it and be able to override it.
  # See testenc20250324.aff in the tests directory.
  flag_covers = {empty_flags => [stem].to_set.clear}

  # Due to memory usage constraints in the main part of the algorithm, we
  # used to have this information earlier, but discarded it and need to
  # rebuild it again. Figure out the mapping between each flag and the
  # wordforms that are generated resulting from that flag. Prefix and
  # suffix flags have a complex interaction, some wordforms are generated
  # only when a specific suffix is paired with a specific prefix. So
  # prefix+suffix pairs are handled as separate entities. Moreover,
  # the cross product settings may forbid or allow combining prefixes
  # with suffixes.
  aff.expand_stem(stem, flags) do |wordform, pfx_flag, sfx_flag, forbidden|
    next if forbidden
    # The caller filters the wordforms and we keep only those that are really useful.
    next unless (yield wordform)
    wordform_dup = wordform.dup
    if pfx_flag && sfx_flag
      # a prefix+suffix pair is an entity of its own
      tmp_flag = aff_flags_merge!(pfx_flag.dup, sfx_flag)
      flag_covers[tmp_flag] = [wordform_dup].to_set unless flag_covers.has_key?(tmp_flag)
      flag_covers[tmp_flag].add(wordform_dup)
    elsif pfx_flag
      flag_covers[pfx_flag] = [wordform_dup].to_set unless flag_covers.has_key?(pfx_flag)
      flag_covers[pfx_flag].add(wordform_dup)
    elsif sfx_flag
      flag_covers[sfx_flag] = [wordform_dup].to_set unless flag_covers.has_key?(sfx_flag)
      flag_covers[sfx_flag].add(wordform_dup)
    end
  end

  # If there's no NEEDAFFIX flag, then every flag combination also additionally produces
  # the stem itself.
  have_needaffix = true
  if aff_flags_empty?(aff.virtual_stem_flag) || !aff_flags_intersect?(flags, aff.virtual_stem_flag)
    have_needaffix = false
    flag_covers.each {|k, v| v.add(stem) }
  end

  # Greedy selection, starting from those flags that cover more wordforms. Ties
  # are resolved by alphabetic sorting of the affix flag names.
  flag_covers_sorted = flag_covers.to_a.sort do |a, b|
    b[1].size == a[1].size ? flag_names[a[0]] <=> flag_names[b[0]] : b[1].size <=> a[1].size
  end
  result_flags = (have_needaffix ? aff.virtual_stem_flag.dup : empty_flags.dup)
  already_covered = [stem].to_set.clear
  flag_covers_sorted.each do |flag, wordforms|
    useful = false
    wordforms.each do |wordform|
      unless already_covered === wordform
        useful = true
        already_covered.add(wordform)
      end
    end
    result_flags = aff_flags_merge!(result_flags, flag) if useful
  end
  result_flags
end

###############################################################################

def try_convert_txt_to_dic(alphabet, aff_file, txt_file, out_file = nil)
  STDERR.puts "== Load «#{aff_file}»" if Cfg.verbose?
  aff = AFF.new(aff_file, alphabet)

  encword_to_idx = {"".bytes => 0}.clear
  idx_to_data = [WordData.new].clear

  subtask "Load «#{txt_file}»" do
    File.open(txt_file).each_line do |line|
      next if (line = line.strip).empty? || line =~ /^#/
      line.split(/[\,\|]/).each do |word|
        word = word.strip
        next if word.empty?
        encword = word.to_8bit
        next if encword_to_idx.has_key?(encword)
        encword_to_idx[encword] = idx_to_data.size
        idx_to_data.push(WordData.new(encword))
      end
    end
  end

  # have normal words below this index, and virtual stems at it and above
  virtual_stem_area_begin = idx_to_data.size

  # Going from wordforms to all possible stems (including the virtual stems
  # that aren't proper wordforms themselves), find the preliminary sets
  # of flags that can be potentially used to construct such wordforms.
  subtask "Find stem candidates and their preliminary affix flags" do
    (0 ... virtual_stem_area_begin).each do |idx|
      aff.lookup_stem(idx_to_data[idx].encword) do |stem, pfx_flag, sfx_flag|
        if (stem_idx = encword_to_idx.fetch(stem, -1)) != -1
          idx_to_data[stem_idx].flags_merge(pfx_flag) if pfx_flag
          idx_to_data[stem_idx].flags_merge(sfx_flag) if sfx_flag
        elsif !aff_flags_empty?(aff.virtual_stem_flag) && !stem.empty?
          stem_dup = stem.dup
          encword_to_idx[stem_dup] = idx_to_data.size
          data = WordData.new(stem_dup)
          data.flags_merge(aff.virtual_stem_flag)
          data.flags_merge(pfx_flag) if pfx_flag
          data.flags_merge(sfx_flag) if sfx_flag
          idx_to_data.push(data)
        end
      end
    end
  end

  # Frequency statistics for different flags usage
  flag_freqs = {"".to_aff_flags => 0}.clear
  flag_names = {"".to_aff_flags => ""} # have a name for the empty flags too
  tmp_covers = [0].to_set.clear

  subtask "Filter out bad affix flags from stems" do
    idx_to_data.each_with_index do |data, idx|
      # Nothing to do for the entries that have no flags to begin with
      next if aff_flags_empty?(data.flags)

      problematic_combined_pfx_sfx = false

      # Going from stems to the wordforms that they produce, identify and
      # remove all invalid flags. First do this for single prefixes and
      # for single suffixes independently from each other.
      aff.expand_stem(data.encword, data.flags) do |wordform, pfx_flag, sfx_flag, forbidden|
        tmpidx = encword_to_idx.fetch(wordform, virtual_stem_area_begin)
        if (!forbidden && (tmpidx >= virtual_stem_area_begin)) ||
            (forbidden && (tmpidx < virtual_stem_area_begin))
          if pfx_flag && sfx_flag
            problematic_combined_pfx_sfx = true
          elsif pfx_flag
            data.flags_delete(pfx_flag)
          elsif sfx_flag
            data.flags_delete(sfx_flag)
          end
        end
      end

      # Nothing left to do if all flags got invalidated
      next if aff_flags_empty?(data.flags)

      if problematic_combined_pfx_sfx
        # Two different flag conflicts resolving strategies: either always favour
        # suffixes or always favour prefixes. Actually there could be theoretically
        # many permutations, but let's keep things simple.
        favor_pfx_flags = nil
        favor_sfx_flags = nil
        aff.expand_stem(data.encword, data.flags) do |wordform, pfx_flag, sfx_flag, forbidden|
          tmpidx = encword_to_idx.fetch(wordform, virtual_stem_area_begin)
          if (!forbidden && (tmpidx >= virtual_stem_area_begin)) ||
              (forbidden && (tmpidx < virtual_stem_area_begin))
            if pfx_flag && sfx_flag
              favor_pfx_flags = aff_flags_delete!(favor_pfx_flags || data.flags.dup, sfx_flag)
              favor_sfx_flags = aff_flags_delete!(favor_sfx_flags || data.flags.dup, pfx_flag)
            elsif pfx_flag || sfx_flag
              raise "should be unreachable"
            end
          end
        end
        if favor_pfx_flags && favor_sfx_flags
          # The "favor prefixes" variant goes to the current slot
          data.flags = favor_pfx_flags
          # Also a new slot is allocated for the "favor suffixes" variant if it's different
          if favor_pfx_flags != favor_sfx_flags
            data2 = WordData.new(data.encword)
            data2.flags = favor_sfx_flags
            idx_to_data.push(data2)
          end
        end
      end

      # Now that all flags are valid, retrive the full list of words that can
      # be generated from this stem
      tmp_covers.clear
      aff.expand_stem(data.encword, data.flags) do |wordform, pfx_flag, sfx_flag, forbidden|
        next if forbidden
        if (tmpidx = encword_to_idx.fetch(wordform, virtual_stem_area_begin)) < virtual_stem_area_begin
          tmp_covers.add(tmpidx)

          # Collect flag names and their usage statistics
          if pfx_flag && sfx_flag
            tmp_flag_dup = aff_flags_merge!(pfx_flag.dup, sfx_flag)
            unless flag_freqs.has_key?(tmp_flag_dup)
              flag_freqs[tmp_flag_dup] = 0
              flag_names[tmp_flag_dup] = aff_flags_to_s(tmp_flag_dup)
            end
            flag_freqs[tmp_flag_dup] += 1
          elsif pfx_flag
            unless flag_freqs.has_key?(pfx_flag)
              tmp_flag_dup = pfx_flag.dup
              flag_freqs[tmp_flag_dup] = 0
              flag_names[tmp_flag_dup] = aff_flags_to_s(tmp_flag_dup)
            end
            flag_freqs[pfx_flag] += 1
          elsif sfx_flag
            unless flag_freqs.has_key?(sfx_flag)
              tmp_flag_dup = sfx_flag.dup
              flag_freqs[tmp_flag_dup] = 0
              flag_names[tmp_flag_dup] = aff_flags_to_s(tmp_flag_dup)
            end
            flag_freqs[sfx_flag] += 1
          end
        end
      end
      data.covers = tmp_covers.to_a
    end
  end

  order = idx_to_data.size.times.to_a
  subtask "Sort stem candidates by the number of their wordforms" do
    order.sort! do |idx1, idx2|
      if idx_to_data[idx2].covers.size == idx_to_data[idx1].covers.size
        if idx_to_data[idx1].encword.size == idx_to_data[idx2].encword.size
          idx_to_data[idx1].encword <=> idx_to_data[idx2].encword
        else
          idx_to_data[idx1].encword.size <=> idx_to_data[idx2].encword.size
        end
      else
        idx_to_data[idx2].covers.size <=> idx_to_data[idx1].covers.size
      end
    end
  end

  # Have a boolean TODO flag for each of the wordforms that needs to be
  # present in the dictionary.
  todo = [true] * virtual_stem_area_begin
  final_result = [tuple2([U8_0], "")].clear

  subtask "Greedily choose useful stems and optimize their affix flags" do
    order.each do |idx|
      data = idx_to_data[idx]
      effectivelycovers = data.covers.count {|idx2| todo[idx2] }
      # It's not useful to have a stem producing only one wordform since we
      # can always just add that wordform itself without any fancy flags.
      if effectivelycovers > 1
        data.flags = optimize_flags(aff, data.encword, data.flags, flag_freqs,
                                    flag_names) {|wordform| todo[encword_to_idx[wordform]] }
        final_result << tuple2(data.encword, aff_flags_to_s(data.flags))
        # remove the result from the TODO list
        data.covers.each {|idx2| todo[idx2] = false }
      end
    end
  end

  subtask "Add the leftover wordforms without any affix flags" do
    todo.each_index do |idx|
      final_result << tuple2(idx_to_data[idx].encword, "") if todo[idx]
    end
  end

  subtask "Write sorted results to «#{out_file ? out_file : "stdout"}»" do
    fh = (out_file ? File.open(out_file, "w") : STDOUT)
    fh.puts final_result.size
    final_result.sort {|a, b| (cmp = a[0].collate(b[0])) == 0 ? a[1] <=> b[1] : cmp }.each do |v|
      fh.puts "#{v[0].to_utf8}#{v[1].empty? ? "" : "/"}#{v[1]}"
    end
    fh.close if out_file
  end
end

def convert_txt_to_dic(aff_file, txt_file, out_file = nil)
  begin
    try_convert_txt_to_dic("", aff_file, txt_file, out_file)
  rescue AlphabetException
    STDERR.puts "! The TRY directive should preferably cover the whole alphabet."
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

input_format = "unk"
output_format = "unk"

args = ARGV.select do |arg|
  if arg =~ /^\-v$/
    Cfg.verbose = true
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
  puts "Copyright © 2025 Siarhei Siamashka. License: CC-BY-SA or MIT."
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
  puts "                             * txt - text file with one word per line, all"
  puts "                                     words are unique and presented in a"
  puts "                                     sorted order (per LC_ALL=C locale)."
  puts "                             * csv - text file with one stem per line,"
  puts "                                     each followed by the comma separated"
  puts "                                     words derived from that stem via"
  puts "                                     applying affixes."
  puts "                             * dic - a .DIC file for Hunspell"
  puts "                             * aff - an automatically reduced .AFF file for"
  puts "                                     Hunspell with comments and redundant"
  puts "                                     affix rules removed."
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
output_format="aff" if output_format == "unk" && args.size >= 3 && args[2] =~ /\.aff$/i

# Default to the comma separated text output
output_format = "csv" if output_format == "unk" && args.size == 2 && input_format == "dic"

# Default to producing a .DIC file if only given text input
output_format = "dic" if output_format == "unk" && args.size == 2 &&
                         (input_format == "txt" || input_format == "csv")

output_format = "aff" if output_format == "unk" && args.size == 2 && input_format == "dic"

###############################################################################

if input_format == "dic" && output_format == "txt" && args.size >= 2
  convert_dic_to_txt(args[0], args[1], nil, (args.size >= 3 ? args[2] : nil))
  exit 0
end

if input_format == "dic" && output_format == "csv" && args.size >= 2
  convert_dic_to_txt(args[0], args[1], ", ", (args.size >= 3 ? args[2] : nil))
  exit 0
end

if input_format == "dic" && output_format == "aff" && args.size >= 2
  Cfg.prune_aff = true
  convert_dic_to_txt(args[0], args[1], nil, (args.size >= 3 ? args[2] : nil))
  exit 0
end

if (input_format == "txt" || input_format == "csv") && output_format == "dic" && args.size >= 2
  convert_txt_to_dic(args[0], args[1], (args.size >= 3 ? args[2] : nil))
  exit 0
end

abort "Don't know how to convert from '#{input_format}' to '#{output_format}'."
