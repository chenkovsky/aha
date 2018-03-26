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
    arr.map { |k, _| String.new k }.sort.should eq(["abc", "abcd", "cde"])

    hash.delete "abcd"
    arr = hash.to_a
    arr.map { |k, _| String.new k }.sort.should eq(["abc", "cde"])
  end

  it "array hash io" do
    hash = Aha::ArrayHash(2).new
    v1 = Bytes.new [3_u8, 4_u8].to_unsafe, 2
    v2 = Bytes.new [5_u8, 6_u8].to_unsafe, 2
    v3 = Bytes.new [7_u8, 8_u8].to_unsafe, 2
    hash["abc"] = v1
    hash["cde"] = v2
    hash["abcd"] = v3
    hash.save "aha.bin"
    hash = Aha::ArrayHash(2).load "aha.bin"
  end
end
