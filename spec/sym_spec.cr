require "./spec_helper"

describe Aha do
  # TODO: Write tests
  it "symspell" do
    matcher = Aha::SymSpell.compile %w(ruby rb Ruby)
    matcher.size.should eq(3)
    matcher.match("ruby", 0).map { |x| x.term }.should eq(["ruby"])
    matcher.match("rub", 0).map { |x| x.term }.should eq([] of String)
    matcher.match("rub", 1).map { |x| x.term }.sort.should eq(["rb", "ruby"])
    matcher.match("rub", 2).map { |x| x.term }.sort.should eq(["Ruby", "rb", "ruby"])
    matcher.match("rub", 2, false).map { |x| x.term }.sort.should eq(["rb", "ruby"])
  end

  it "symspell save load" do
    matcher = Aha::SymSpell.compile %w(ruby rb Ruby)
    matcher.save("sym.bin")
    matcher = Aha::SymSpell.load("sym.bin")
    matcher.size.should eq(3)
    matcher.match("ruby", 0).map { |x| x.term }.should eq(["ruby"])
    matcher.match("rub", 0).map { |x| x.term }.should eq([] of String)
    matcher.match("rub", 1).map { |x| x.term }.sort.should eq(["rb", "ruby"])
    matcher.match("rub", 2).map { |x| x.term }.sort.should eq(["Ruby", "rb", "ruby"])
    matcher.match("rub", 2, false).map { |x| x.term }.sort.should eq(["rb", "ruby"])
  end
end
