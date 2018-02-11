require "./spec_helper"

describe Aha do
  # TODO: Write tests
  it "wu" do
    matcher = Aha::WuManber.compile %w(我 我是 是中)
    matched = [] of Tuple(Int32, Int32)
    matcher.match("我是中国人") do |hit|
      matched << ({hit.end, hit.value})
    end
    matched.should eq([{1, 0}, {2, 1}, {3, 2}])
  end

  it "wu save load" do
    matcher = Aha::WuManber.compile %w(我 我是 是中)
    STDERR.puts "before save"
    matcher.save("aha.bin")
    STDERR.puts "before load"
    machter = Aha::WuManber.load("aha.bin")
    STDERR.puts "after load"
    matched = [] of Tuple(Int32, Int32)
    matcher.match("我是中国人") do |hit|
      matched << ({hit.end, hit.value})
    end
    matched.should eq([{1, 0}, {2, 1}, {3, 2}])
  end
end
