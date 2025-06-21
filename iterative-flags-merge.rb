round = 0
while true
  STDERR.puts "== Round #{round += 1} =="
  `./flagsfreq words_final.dic words_final.aff > best_multibundle.aff`
  if $? != 0
    STDERR.puts "== Nothing to improve anymore =="
    exit 0
  end
  `cat words_final.aff best_multibundle.aff > tmp.aff`
  `./hunaftool tmp.aff words.txt words_final.dic`
  `./hunaftool tmp.aff words_final.dic words_final.aff`
  `ls -l words_final.dic`
  `wc -l words_final.dic`
  `cat words_final.aff words_final.dic > merged.txt`
  `ls -l merged.txt`
end
