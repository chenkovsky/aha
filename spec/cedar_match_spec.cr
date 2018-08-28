require "./spec_helper"

describe Aha do
  it "cedar match" do
    trie = Aha::CedarBig.new
    ids = %w(Ruby ruby rub).map do |s|
      trie.insert s
    end

    ans = [{0, 4, "Ruby"}, {8, 11, "rub"}]
    ms = [] of Tuple(Int32, Int32, String)
    trie.match_longest("Ruby on rub", false) do |m|
      ms << {m.start, m.end, trie[m.value]}
    end
    ms.should eq(ans)
  end

  it "cedar match ignore case" do
    trie = Aha::CedarBig.new
    ids = %w(Ruby ruby rub).map do |s|
      trie.insert s
    end

    ans = [{0, 4, "Ruby"}, {8, 12, "ruby"}]
    ms = [] of Tuple(Int32, Int32, String)
    trie.match_longest("Ruby on ruby", true) do |m|
      ms << {m.start, m.end, trie[m.value]}
    end
    ms.sort.should eq(ans)
  end

  it "cedar gsub" do
    trie = Aha::CedarBig.new
    ids = %w(Ruby ruby rub).map do |s|
      trie.insert s
    end
    str = trie.gsub("Ruby on ruby rub", true) do |m|
      case trie[m.value]
      when "ruby"
        "crystal"
      when "Ruby"
        "Crystal"
      else
        "Unknown"
      end
    end

    str.should eq("Crystal on crystal Unknown")
  end

  it "cedar sep match" do
    trie = Aha::CedarBig.new
    ids = %w(Ruby ruby rub).map do |s|
      trie.insert s
    end

    ans = [{0, 4, "Ruby"}, {20, 24, "ruby"}]
    ms = [] of Tuple(Int32, Int32, String)
    trie.match_longest("Ruby rRuby on rubyx ruby", true, sep: [' ']) do |m|
      ms << {m.start, m.end, trie[m.value]}
    end
    ms.sort.should eq(ans)
  end

  it "cedar sep gsub" do
    trie = Aha::CedarBig.new
    ids = %w(Ruby ruby rub).map do |s|
      trie.insert s
    end
    s = trie.gsub("Ruby rRuby on rubyx ruby", true, sep: [' ']) do |m|
      case trie[m.value]
      when "ruby"
        "crystal"
      when "Ruby"
        "Crystal"
      else
        "Unknown"
      end
    end
    s.should eq("Crystal rRuby on rubyx crystal")
  end

  it "cedar reverse match" do
    trie = Aha::Cedar.new
    ids = %w(s' S' S'').map do |s|
      trie.insert s
    end

    ans = [{"S'", 2}, {"S''", 3}]
    ms = [] of Tuple(String, Int32)
    trie.reverse_suffix("She''S".chars, false) do |vk, char_num|
      ms << ({trie[vk], char_num})
    end
    ms.sort.should eq(ans)
  end

  it "cedar bytes reverse match" do
    trie = Aha::Cedar.new
    ids = %w(s' S' S'').map do |s|
      trie.insert s
    end
    ans = [{"S'", 2}, {"S''", 3}]
    ms = [] of Tuple(String, Int32)
    trie.reverse_suffix("She''S".bytes) do |vk, byte_num|
      ms << ({trie[vk], byte_num})
    end
    ms.sort.should eq(ans)
  end
end
