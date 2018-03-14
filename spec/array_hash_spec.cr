require "./spec_helper"

describe Aha do
  it "array hash" do
    hash = Aha::ArrayHash(2).new
    v1 = Bytes.new [3_u8, 4_u8].to_unsafe, 2
    v2 = Bytes.new [5_u8, 6_u8].to_unsafe, 2
    v3 = Bytes.new [7_u8, 8_u8].to_unsafe, 2
    hash["abc"] = v1
    hash["cde"] = v2
    hash["abcd"] = v3
    hash["abc"].should eq(v1)
    hash["cde"].should eq(v2)
    hash["abcd"].should eq(v3)
    arr = hash.to_a
    arr.map { |x| String.new x.key }.sort.should eq(["abc", "abcd", "cde"])
    arr.map { |x| x.value }.should eq([v1, v2, v3])

    hash.delete "abcd"
    arr = hash.to_a
    arr.map { |x| String.new x.key }.sort.should eq(["abc", "cde"])
    arr.map { |x| x.value }.should eq([v1, v2])
  end

  it "array hash io" do
  end
end
