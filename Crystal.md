## 

Hunaftool is implemented using a common subset of Ruby and Crystal.

## Some practical recommendations

### Detection if running under Ruby or Crystal

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

### Using integers of different sizes without breaking compatibility with Ruby

```Ruby
# Monkey-patch Ruby to make it recognize the Crystal's .to_i128 method
class Integer def to_i128() to_i end end

# An 8-bit zero constant to hint the use of UInt8 instead of Int32 for Crystal
U8_0 = "\0".bytes.first

# A 64-bit zero constant to hint the use of Int64 instead of Int32 for Crystal
I64_0 = (0x3FFFFFFFFFFFFFFF & 0)

# A 128-bit zero constant to hint the use of Int128 instead of Int32 for Crystal
I128_0 = 0.to_i128
```
