# aha

ahocorasick algorithm based on cedar which is a high performance double array trie.

## Installation

Add this to your application's `shard.yml`:

```yaml
dependencies:
  aha:
    github: chenkovsky/aha
```

## Usage

```crystal
require "aha"
it "save load" do
    matcher = Aha.compile %w(我 我是 是中)
    matcher.save("aha.bin") # serialize automata into file
    machter = Aha.load("aha.bin") # load automata from file
    matched = [] of Tuple(Int32, Int32)
    matcher.match("我是中国人") do |hit|
      matched << ({hit.end, hit.value})
    end
    matched.should eq([{1, 0}, {2, 1}, {3, 2}])
end
```


## Development

TODO: Write development instructions here

## Contributing

1. Fork it ( https://github.com/chenkovsky/aha/fork )
2. Create your feature branch (git checkout -b my-new-feature)
3. Commit your changes (git commit -am 'Add some feature')
4. Push to the branch (git push origin my-new-feature)
5. Create a new Pull Request

## Contributors

- [chenkovsky](https://github.com/chenkovsky) chenkovsky - creator, maintainer
