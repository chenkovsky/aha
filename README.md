# aha

ahocorasick automaton based on cedar which is a high performance double array trie. semi-dynamic ahocorasick automaton based.

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
    matcher = Aha::AC.compile %w(我 我是 是中)
    matcher.save("aha.bin") # serialize automata into file
    machter = Aha::AC.load("aha.bin") # load automata from file
    matched = [] of Tuple(Int32, Int32)
    matcher.match("我是中国人") do |hit|
      matched << ({hit.end, hit.value})
    end
    matched.should eq([{1, 0}, {2, 1}, {3, 2}])
end

  it "dynamic ac" do
    matcher = Aha::DAC.compile %w(我 我是 是中)
    matched = [] of Tuple(Int32, Int32)
    matcher.match("我是中国人") do |hit|
      matched << ({hit.end, hit.value})
    end
    matched.should eq([{1, 0}, {2, 1}, {3, 2}])
    matcher.insert("中国")
    matched = [] of Tuple(Int32, Int32)
    matcher.match("我是中国人") do |hit|
      matched << ({hit.end, hit.value})
    end
    matched.should eq([{1, 0}, {2, 1}, {3, 2}, {4, 2}])
  end

  it "dynamic ac save load" do
    matcher = Aha::DAC.compile %w(我 我是 是中 中国)
    matcher.save("aha.bin")
    matcher = Aha::DAC.load("aha.bin")
    matched = [] of Tuple(Int32, Int32)
    matcher.match("我是中国人") do |hit|
      matched << ({hit.end, hit.value})
    end
    matched.should eq([{1, 0}, {2, 1}, {3, 2}, {4, 2}])
  end
```

# TODO

[] implement DAWG

[] dynamic AC


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
