require "./spec_helper"

describe Aha do
  # TODO: Write tests
  it "cedar insert delete" do
    trie = Aha::Cedar.new
    ids = %w(Ruby ruby rb).map do |s|
      trie.insert s
    end
    ids.should eq([0, 1, 2])
    trie.delete("ruby").should eq(1)
    trie.delete("ruby").should eq(-1)
  end
  it "cedar iter" do
    trie = Aha::Cedar.new(true)
    ids = %w(Ruby ruby rb XX).map do |s|
      trie.insert s
    end
    trie.to_a.map { |t| {t.key, t.value} }.should eq([{"Ruby", 0}, {"XX", 3}, {"rb", 2}, {"ruby", 1}])
    arr = [] of Tuple(String, Int32)
    trie.bfs_each { |t| arr << ({t.key, t.value}) }
    arr.should eq([{"XX", 3}, {"rb", 2}, {"Ruby", 0}, {"ruby", 1}])
  end
end
