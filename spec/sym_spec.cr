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

  it "symspell compound" do
    vocab = %w(can you read this message despite the horrible spelling mistakes)
    matcher = Aha::SymSpell.compile Hash.zip(vocab, vocab.map { |_| 10 })
    matched = matcher.match(%w(Can yu readthis messa ge despite thehorible sppelingmsitakes))
    matched.size.should eq(1)
    matched[0].term.should eq("can you read this message despite the horrible spelling mistakes")
    matched[0].distance.should eq(10)
  end
end
