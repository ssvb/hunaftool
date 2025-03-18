# hunaftool
This tool is primarily designed to assist in developing and maintaining
dictionaries for [Hunspell](https://github.com/hunspell/hunspell). As
such, it can be used to validate the correctness of existing
dictionaries and fintune/optimize '''.dic''' files.

The end users may be interested in extracting human readable lists of
words in text format from the affix-compressed Hunspell dictionaries.

## Supported affix options

The checked ones are supported by **hunaftool**:

###### General

*   [ ] `SET encoding` (UTF-8 is implied)
*   [ ] `FLAG long`
*   [ ] `COMPLEXPREFIXES`
*   [ ] `LANG langcode`
*   [ ] `IGNORE characters`
*   [ ] `AF number_of_flag_vector_aliases`

###### Suggestion

*   [x] `TRY characters`
*   [ ] `NOSUGGEST flag`
*   [ ] `MAXCPDSUGS num`
*   [ ] `MAXNGRAMSUGS num`
*   [ ] `MAXDIFF [0-10]`
*   [ ] `ONLYMAXDIFF`
*   [ ] `NOSPLITSUGS`
*   [ ] `SUGSWITHDOTS`
*   [ ] `REP number_of_replacement_definitions`
*   [ ] `REP what replacement`
*   [ ] `MAP number_of_map_definitions`
*   [ ] `MAP string_of_related_chars_or_parenthesized_character_sequences`
*   [ ] `PHONE number_of_phone_definitions`
*   [ ] `PHONE what replacement`
*   [ ] `WARN flag`
*   [ ] `FORBIDWARN`

###### Compounding

*   [ ] `BREAK number_of_break_definitions`
*   [ ] `BREAK character_or_character_sequence`
*   [ ] `COMPOUNDRULE number_of_compound_definitions`
*   [ ] `COMPOUNDRULE compound_pattern`
*   [ ] `COMPOUNDMIN num`
*   [ ] `COMPOUNDFLAG flag`
*   [ ] `COMPOUNDBEGIN flag`
*   [ ] `COMPOUNDLAST flag`
*   [ ] `COMPOUNDMIDDLE flag`
*   [ ] `ONLYINCOMPOUND flag`
*   [ ] `COMPOUNDPERMITFLAG flag`
*   [ ] `COMPOUNDFORBIDFLAG flag`
*   [ ] `COMPOUNDMORESUFFIXES`
*   [ ] `COMPOUNDROOT flag`
*   [ ] `COMPOUNDWORDMAX number`
*   [ ] `CHECKCOMPOUNDDUP`
*   [ ] `CHECKCOMPOUNDREP`
*   [ ] `CHECKCOMPOUNDCASE`
*   [ ] `CHECKCOMPOUNDTRIPLE`
*   [ ] `SIMPLIFIEDTRIPLE`
*   [ ] `CHECKCOMPOUNDPATTERN number_of_checkcompoundpattern_definitions`
*   [ ] `CHECKCOMPOUNDPATTERN endchars[/flag] beginchars[/flag] [replacement]`
*   [ ] `FORCEUCASE flag`
*   [ ] `COMPOUNDSYLLABLE max_syllable vowels`
*   [ ] `SYLLABLENUM flags`

###### Affix creation

*   [x] `PFX flag cross_product number`
*   [x] `PFX flag stripping prefix [condition [morphological_fields…]]`
*   [x] `SFX flag cross_product number`
*   [x] `SFX flag stripping suffix [condition [morphological_fields…]]`

###### Other

*   [ ] `CIRCUMFIX flag`
*   [ ] `FORBIDDENWORD flag`
*   [ ] `FULLSTRIP`
*   [ ] `KEEPCASE flag`
*   [ ] `ICONV number_of_ICONV_definitions`
*   [ ] `ICONV pattern pattern2`
*   [ ] `OCONV number_of_OCONV_definitions`
*   [ ] `OCONV pattern pattern2`
*   [ ] `LEMMA_PRESENT flag`
*   [ ] `NEEDAFFIX flag`
*   [ ] `PSEUDOROOT flag`
*   [ ] `SUBSTANDARD flag`
*   [ ] `WORDCHARS characters`
*   [ ] `CHECKSHARPS`

## License

This work is dual-licensed under:
* [MIT](LICENSE) © Siarhei Siamashka
* [CC-BY-SA-3.0 or later](LICENSE.CC-BY-SA-3.0) © Siarhei Siamashka

You can choose any of these licenses if you use this work.
