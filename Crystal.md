## 

Hunaftool is implemented using a common subset of Ruby and Crystal.

## Some practical recommendations

Detection if running under Ruby or Crystal:

```Ruby
# This is how runing under Crystal can be detected.
COMPILED_BY_CRYSTAL = (((1 / 2) * 2) != 0)

if COMPILED_BY_CRYSTAL
  puts "I'm compiled by Crystal."
else
  puts "I'm running in a Ruby interpreter."
end
```

Explanation: this check relies on the fact that Crystal has a different integer division rounding.