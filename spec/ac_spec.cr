require "./spec_helper"

describe Aha do
  # TODO: Write tests
  it "ac" do
    matcher = Aha::AC.compile %w(我 我是 是中)
    matched = [] of Tuple(Int32, Int32)
    matcher.match("我是中国人") do |hit|
      matched << ({hit.end, hit.value})
    end
    matched.should eq([{1, 0}, {2, 1}, {3, 2}])
  end

  it "ac save load" do
    matcher = Aha::AC.compile %w(我 我是 是中)
    matcher.save("aha.bin")
    machter = Aha::AC.load("aha.bin")
    matched = [] of Tuple(Int32, Int32)
    matcher.match("我是中国人") do |hit|
      matched << ({hit.end, hit.value})
    end
    matched.should eq([{1, 0}, {2, 1}, {3, 2}])
  end

  it "ac with sep" do
    matcher = Aha::AC.compile %w(a aa)
    matched = [] of Tuple(Int32, Int32)
    sep = BitArray.new(256)
    sep[' '.ord] = true
    matcher.match("a aaa", sep) do |hit|
      matched << ({hit.end, hit.value})
    end
    matched.should eq([{1, 0}])
  end
end
