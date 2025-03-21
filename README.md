# Hunaftool [![linux](https://github.com/ssvb/hunaftool/actions/workflows/linux.yml/badge.svg)](https://github.com/ssvb/hunaftool/actions/workflows/linux.yml) [![windows](https://github.com/ssvb/hunaftool/actions/workflows/windows.yml/badge.svg)](https://github.com/ssvb/hunaftool/actions/workflows/windows.yml)

This tool is primarily designed to assist in the development and maintenance of
[Hunspell](https://github.com/hunspell/hunspell) dictionaries.
It can be used to validate correctness of the existing dictionaries.
But more importantly, it can automatically create a `.dic` file tailored for a specific `.aff` file.

End users may be interested in extracting human-readable lists of words in text format from the affix-compressed Hunspell dictionaries.

## Usage

The tool requires Ruby interpreter (https://www.ruby-lang.org) or Crystal compiler (https://crystal-lang.org) in just a baseline configuration without any extra gems or shards.

```
hunaftool v0.7 - automated conversion between plain text word lists
                 and .DIC files for Hunspell, tailoring them for some
                 already existing .AFF file with affixes.
Copyright © 2025 Siarhei Siamashka. License: CC BY-SA 4.0 or MIT.

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

Replicates the functionality of `unmunch` tool, minus its bugs.

### Compressing a word list into a dictionary

Replicates the functionality of `munch` tool, minus its bugs.

## Limitations

* The Ruby interpreter is slow and the Crystal compiler [isn't readily available](https://crystal-lang.org/reference/1.15/syntax_and_semantics/platform_support.html)
on every platform (Windows is a 3rd tier platform with limited support).
* The tool is Unicode-aware, but it only supports up to 256 unique characters in the whole
dictionary, which makes it not suitable for the languages that use hieroglyphs. Internally
the strings are remapped to a 8-bit representation for reducing memory footprint and
fast child node lookups in a [Trie data structure](https://en.wikipedia.org/wiki/Trie).
If this happens, the tool will bail out with an error message rather than silently producing incorrect results.
* Processing some dictionaries may require huge amounts of memory, well beyond what is available on your computer.
* Hunspell compatibility is incomplete and the following options are NOT supported:
`SET encoding`,
`COMPLEXPREFIXES`,
`LANG langcode`,
`IGNORE characters`,
`AF number_of_flag_vector_aliases`,
`WARN flag`,
`FORBIDWARN`,
`CIRCUMFIX flag`,
`FORBIDDENWORD flag`,
`KEEPCASE flag`,
`LEMMA_PRESENT flag`,
`PSEUDOROOT flag`,
`SUBSTANDARD flag`,
`CHECKSHARPS`,
`COMPOUNDRULE`

## License

This work is dual-licensed under:
* [MIT](LICENSE.MIT) © Siarhei Siamashka
* [CC-BY-SA-3.0 or later](LICENSE.CC-BY-SA) © Siarhei Siamashka

You can choose any of these licenses if you use this work.
