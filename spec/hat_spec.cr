require "./spec_helper"

describe Aha do
  it "hat trie" do
    v1 = Bytes.new [3_u8, 4_u8].to_unsafe, 2
    v2 = Bytes.new [5_u8, 6_u8].to_unsafe, 2
    v3 = Bytes.new [7_u8, 8_u8].to_unsafe, 2
    v4 = Bytes.new [9_u8, 10_u8].to_unsafe, 2
    trie = Aha::Hat(2).new
    trie["ab"] = v1
    trie["bc"] = v2
    trie["abc"] = v3
    trie["abcd"] = v4
    trie["ab"].should eq(v1)
    trie["bc"].should eq(v2)
    trie["abc"].should eq(v3)
    trie["abcd"].should eq(v4)
    arr = [] of String
    trie.each do |kv|
      arr << (String.new kv.key)
    end
    arr.sort.should eq(["ab", "abc", "abcd", "bc"])
  end
end
