require "./spec_helper"

describe Aha do
  it "hat trie" do
    trie = Aha::Hat.compile({
      "ab"  => 2_u64,
      "bc"  => 3_u64,
      "abc" => 4_u64,
    })

    trie["abcd"] = 5_u64
    trie["bc"].should eq(3_u64)
    trie["abcd"].should eq(5_u64)
    arr = [] of Tuple(String, UInt64)
    trie.each do |k, v|
      arr << ({String.new k, v})
    end
    trie.sort.should eq([{"ab", 2_u64}, {"abc", 4_u64}, {"abcd", 5_u64}, {"bc", 3_u64}])
  end
end
