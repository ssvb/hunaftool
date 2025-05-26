# Hunaftool
[![linux](https://github.com/ssvb/hunaftool/actions/workflows/linux.yml/badge.svg)](https://github.com/ssvb/hunaftool/actions/workflows/linux.yml) [![linux executable](https://img.shields.io/badge/linux_executable-black?logo=crystal)](https://nightly.link/ssvb/hunaftool/workflows/linux/main)
[![windows](https://github.com/ssvb/hunaftool/actions/workflows/windows.yml/badge.svg)](https://github.com/ssvb/hunaftool/actions/workflows/windows.yml) [![windows executable](https://img.shields.io/badge/windows_executable-black?logo=crystal)](https://nightly.link/ssvb/hunaftool/workflows/windows/main)
# https://nightly.link/ssvb/hunaftool/workflows/linux/main
# https://nightly.link/ssvb/hunaftool/workflows/windows/main

This tool is primarily designed to assist in the development and maintenance of
[Hunspell](https://github.com/hunspell/hunspell) dictionaries.
It can be used to validate correctness of the existing dictionaries.
But more importantly, it can automatically create a `.dic` file tailored for a specific `.aff` file.
Essentially, the functionality of `munch` and `unmunch` tools is replicated, but with Unicode support and without their bugs.

End users may be interested in extracting human-readable lists of words in text format from the affix-compressed Hunspell dictionaries.

## Usage

The tool requires [Ruby](https://www.ruby-lang.org) interpreter or [Crystal](https://crystal-lang.org) compiler in just a baseline configuration without any extra gems or shards.

```
$ ruby hunaftool.rb
hunaftool v0.8 - automated conversion between plain text word lists
                 and .DIC files for Hunspell, tailoring them for some
                 already existing .AFF file with affixes.
Copyright © 2025 Siarhei Siamashka. License: CC BY-SA 3.0+ or MIT.

Usage: hunaftool [options] <whatever.aff> [input_file] [output_file]
Where options can be:
  -v                      : verbose diagnostic messages to stderr

  -i=[dic|txt|csv]        : the input file format:
                             * txt - plain word list with one word per line
                             * csv - same as txt, but more than one word
                                     is allowed in a line and they are
                                     comma separated
                             * dic - a .DIC file from Hunspell

  -o=[dic|txt|csv|js|lua] : the desired output file format:
                             * txt - text file with one word per line,
                                     all words are unique and presented
                                     in a sorted order.
                             * csv - text file with one stem per line,
                                     each of them followed by the comma
                                     separated words that had been derived
                                     from it via applying affixes.
                             * dic - a .DIC file for Hunspell
                             * js  - JavaScript code (TODO)
                             * lua - Lua code (TODO)

An example of extracting all words from a dictionary:
    ruby hunaftool.rb -i=dic -o=txt be_BY.aff be_BY.dic be_BY.txt

An example of creating a .DIC file from an .AFF file and a word list:
    ruby hunaftool.rb -i=txt -o=dic be_BY.aff be_BY.txt be_BY.dic

If the input and output formats are not provided via -i/-o options,
then they are automatically guessed from file extensions. If the
output file is not provided, then the result is printed to stdout.
```

### Extracting words from a dictionary

An example of extracting `wordlist.txt` from a Belarusian dictionary:

```bash
$ wget https://github.com/mikalai-udodau/spell-be/releases/download/rel-0.60/hunspell-be-0.60.zip
$ unzip hunspell-be-0.60.zip
$ ruby hunaftool.rb be_BY.aff be_BY.dic wordlist.txt
! Invalid flag «C» is referenced from the flags field «OC».
! Invalid flag «/» is referenced from the flags field «E/E».
```

Please pay attention to the diagnistic messages. Upon encountering something
erroneous or ambiguous in a dictionary, Hunspell in its default configuration
just [silently](https://github.com/hunspell/hunspell/issues/1046)
interprets it in some deterministic manner. In this particular case invalid
affix flags are ignored by Hunspell. While doing the conversion, Hunaftool
tries to accurately emulate the Hunspell's behaviour, but also doesn't
shy away from complaining about the potential problems.

### Compressing a word list into a dictionary

An example of converting a potentially edited word list back into the
affix-compressed `.dic` format.
```
$ time ruby hunaftool.rb be_BY.aff wordlist_edited.txt be_BY_edited.dic

real	1m48.307s
user	1m47.892s
sys	0m0.410s
```

But as this operation demands a lot of computational power,
it's better to use Crystal instead of Ruby for a roughly up
to x20 times performance increase. The tool can be compiled
via `crystal build --release hunaftool.rb` command. And then:
```
$ time ./hunaftool be_BY.aff wordlist_edited.txt be_BY_edited.dic

real	0m6.857s
user	0m7.525s
sys	0m0.100s
```
Much faster!

## Limitations

* The Ruby interpreter is slow and the Crystal compiler [isn't readily available](https://crystal-lang.org/reference/1.15/syntax_and_semantics/platform_support.html)
on every platform (Windows is a 3rd tier platform with limited support).
* The tool is Unicode-aware, but it only supports up to 256 unique characters in the whole
dictionary, which makes it not practically suitable for the languages that use hieroglyphs. Internally
the strings are remapped to a 8-bit representation for reducing memory footprint and
fast child node lookups in a [Trie](https://en.wikipedia.org/wiki/Trie) data structure.
If this happens, the tool will bail out with an error message rather than silently producing incorrect results.
* Processing some dictionaries may require huge amounts of memory, well beyond what is available on your computer.
* Hunspell compatibility is incomplete and the following options are **NOT** supported:
`SET encoding`,
`COMPLEXPREFIXES`,
`LANG langcode`,
`IGNORE characters`,
`AF number_of_flag_vector_aliases`,
`AM number_of_morphological_aliases`,
`NOSUGGEST flag`
`WARN flag`,
`FORBIDWARN`,
`COMPOUNDRULE number_of_compound_definitions`,
`COMPOUNDRULE compound_pattern`,
`COMPOUNDMIN num`,
`COMPOUNDFLAG flag`,
`COMPOUNDBEGIN flag`,
`COMPOUNDLAST flag`,
`COMPOUNDMIDDLE flag`,
`ONLYINCOMPOUND flag`,
`COMPOUNDPERMITFLAG flag`,
`COMPOUNDFORBIDFLAG flag`,
`COMPOUNDMORESUFFIXES`,
`COMPOUNDROOT flag`,
`COMPOUNDWORDMAX number`,
`CHECKCOMPOUNDDUP`,
`CHECKCOMPOUNDREP`,
`CHECKCOMPOUNDCASE`,
`CHECKCOMPOUNDTRIPLE`,
`SIMPLIFIEDTRIPLE`,
`CHECKCOMPOUNDPATTERN number_of_checkcompoundpattern_definitions`
`FORCEUCASE flag`,
`COMPOUNDSYLLABLE max_syllable vowels`,
`SYLLABLENUM flags`
`CIRCUMFIX flag`,
`FORBIDDENWORD flag`,
`KEEPCASE flag`,
`ICONV number_of_ICONV_definitions`,
`OCONV number_of_OCONV_definitions`,
`LEMMA_PRESENT flag`,
`PSEUDOROOT flag`,
`SUBSTANDARD flag`,
`CHECKSHARPS`.

## License

Hunaftool is dual-licensed under [MIT](LICENSE.MIT) OR [CC-BY-SA-3.0 or later](LICENSE.CC-BY-SA).
You may select, at your option, one of these licenses if you use this work.
