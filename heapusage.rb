dicname  = ARGV[0]
wordlist = ARGV[1]

result = `heaptrack hunspell -d #{dicname} -l #{wordlist}`
if result =~ /(heaptrack \-\-analyze.*)/
  result2 = `#{$1.strip}`
  if result2 =~ /peak heap memory consumption\: (\S+)/
    puts "Peak heap usage: #{$1}"
  end
end
