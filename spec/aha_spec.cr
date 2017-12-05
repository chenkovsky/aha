require "./spec_helper"

describe Aha do
  # TODO: Write tests
  it "works" do
    matcher = Aha.compile %w(我 我是 是中)
    matched = [] of Tuple(Int32, Int32)
    matcher.match("我是中国人") do |hit|
      matched << ({hit.end, hit.value})
    end
    matched.should eq([{0, 0}, {1, 1}, {2, 2}])
  end
end
