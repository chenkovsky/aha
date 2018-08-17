require "./spec_helper"

describe Aha do
  # TODO: Write tests
  it "not intersectable" do
    trie = Aha::Cedar.new
    ids = %w(Ruby ruby rub).map do |s|
      trie.insert s
    end
    ac = Aha::AC.compile trie

    ans = [{0, 4, "Ruby"}, {8, 11, "rub"}]
    ms = [] of Tuple(Int32, Int32, String)
    ac.match_longest("Ruby on rub") do |m|
      ms << {m.start, m.end, ac[m.value]}
    end
    ms.should eq(ans)
  end

  it "intersectable" do
    trie = Aha::Cedar.new
    ids = ["Ruby", "ruby", "uby "].map do |s|
      trie.insert s
    end
    ac = Aha::AC.compile trie

    ans = [{0, 4, "ruby"}, {1, 5, "uby "}]
    ms = [] of Tuple(Int32, Int32, String)
    ac.match_longest("ruby ", true) do |m|
      ms << {m.start, m.end, ac[m.value]}
    end
    ms.should eq(ans)
  end
end
