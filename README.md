# Hunaftool [![linux](https://github.com/ssvb/hunaftool/actions/workflows/linux.yml/badge.svg)](https://github.com/ssvb/hunaftool/actions/workflows/linux.yml) [![amd64](https://img.shields.io/badge/amd64-black?logo=crystal)](https://nightly.link/ssvb/hunaftool/workflows/linux/main) [![windows](https://github.com/ssvb/hunaftool/actions/workflows/windows.yml/badge.svg)](https://github.com/ssvb/hunaftool/actions/workflows/windows.yml) [![x64](https://img.shields.io/badge/x64-black?logo=crystal)](https://nightly.link/ssvb/hunaftool/workflows/windows/main)
Automatic manipulation and conversion of Hunspell dictionary files

## Usage

```
hunaftool v0.8 - automated conversion between plain text word lists
                 and .DIC files for Hunspell, tailoring them for some
                 already existing .AFF file with affixes.
Copyright © 2025 Siarhei Siamashka. License: CC-BY-SA or MIT.

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
                             * txt - text file with one word per line, all
                                     words are unique and presented in a
                                     sorted order (per LC_ALL=C locale).
                             * csv - text file with one stem per line,
                                     each followed by the comma separated
                                     words derived from that stem via
                                     applying affixes.
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

## License

Hunaftool is dual-licensed under [MIT](LICENSE.MIT) OR [CC-BY-SA-3.0 or later](LICENSE.CC-BY-SA).
You may select, at your option, one of these licenses if you use this work.
