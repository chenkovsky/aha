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

  it "sam" do
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
end
