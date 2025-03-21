# Hunaftool [![linux](https://github.com/ssvb/hunaftool/actions/workflows/linux.yml/badge.svg)](https://github.com/ssvb/hunaftool/actions/workflows/linux.yml) [![windows](https://github.com/ssvb/hunaftool/actions/workflows/windows.yml/badge.svg)](https://github.com/ssvb/hunaftool/actions/workflows/windows.yml)

This tool is primarily designed to assist in developing and maintaining
dictionaries for [Hunspell](https://github.com/hunspell/hunspell).
It can be used to validate correctness of the existing
[dictionaries](https://manpages.ubuntu.com/manpages/xenial/man5/hunspell.5.html#short%20example).
But more importantly, it can automatically create a [.dic](https://manpages.ubuntu.com/manpages/xenial/man5/hunspell.5.html#dictionary%20file)
file tailored for a specific `.aff` file.

The end users may be interested in extracting human readable lists of
words in text format from the affix-compressed Hunspell dictionaries.

## Extracting words from a dictionary

Replicates the functionality of `unmunch` tool, minus its bugs and limitations.

## Compressing a word list into a dictionary

Replicates the functionality of `munch` tool, minus its bugs and limitations.

## Limitations

* The Ruby interpreter is slow and the Crystal compiler [isn't readily available](https://crystal-lang.org/reference/1.15/syntax_and_semantics/platform_support.html)
on every platform (Windows is a 3rd tier platform with limited support).
* The tool is Unicode-aware, but it only supports up to 256 unique characters in the whole
dictionary, which makes it not suitable for the languages that use hieroglyphs. Internally
the strings are remapped to a 8-bit representation for reducing memory footprint and
fast child node lookups in a [Trie data structure](https://en.wikipedia.org/wiki/Trie).
If this happens, the tool will bail out with an error message rather than producing incoddect results.
* Processing some dictionaries may require huge amounts of memory, well beyond what is available on your computer.
* Hunspell compatibility is limited and the following options are NOT supported:
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
* [CC-BY-SA-3.0 or later](LICENSE) © Siarhei Siamashka
* [MIT](LICENSE.MIT) © Siarhei Siamashka

You can choose any of these licenses if you use this work.
