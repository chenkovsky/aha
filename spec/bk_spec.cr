require "./spec_helper"

describe Aha do
  it "bk tree" do
    tree = Aha::BKTree.compile(["ab", "bc", "abc"])
    key_dist_arr = [] of Tuple(String, Int32)
    tree.match("abc", 0) do |key, dist|
      key_dist_arr << ({key, dist})
    end
    key_dist_arr.should eq([{"abc", 0}])
    key_dist_arr.clear
    tree.match("abc", 1) do |key, dist|
      key_dist_arr << ({key, dist})
    end
    key_dist_arr.sort.should eq([{"ab", 1}, {"abc", 0}, {"bc", 1}])
  end
end
