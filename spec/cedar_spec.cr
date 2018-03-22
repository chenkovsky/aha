require "./spec_helper"

describe Aha do
  # it "cedar insert delete" do
  #   trie = Aha::Cedar.new
  #   ids = %w(Ruby ruby rb).map do |s|
  #     trie.insert s
  #   end
  #   ids.should eq([0, 1, 2])
  #   trie.delete("ruby").should eq(1)
  #   trie.delete("ruby").should eq(-1)
  # end
  # it "cedar iter" do
  #   trie = Aha::Cedar.new(true)
  #   ids = %w(Ruby ruby rb XX).map do |s|
  #     trie.insert s
  #   end
  #   arr = [] of Tuple(String, Int32)
  #   trie.dfs_each { |t| arr << ({t.key, t.value}) }
  #   arr.should eq([{"Ruby", 0}, {"XX", 3}, {"rb", 2}, {"ruby", 1}])
  #   arr.clear
  #   trie.bfs_each { |t| arr << ({t.key, t.value}) }
  #   arr.should eq([{"XX", 3}, {"rb", 2}, {"Ruby", 0}, {"ruby", 1}])
  #   trie.to_a.map { |t| {t.key, t.value} }.should eq([{"Ruby", 0}, {"ruby", 1}, {"rb", 2}, {"XX", 3}])
  # end

  it "pos testcase" do
    poses = <<-POSSET
$ SYM
''  PUNCT
, PUNCT
-LRB- PUNCT
-RRB- PUNCT
. PUNCT
: PUNCT
ADD X
AFX ADJ
CC  CCONJ
CD  NUM
DT  DET
EX  ADV
FW  X
HYPH  PUNCT
IN  ADP
JJ  ADJ
JJR ADJ
JJS ADJ
LS  PUNCT
MD  VERB
NFP PUNCT
NN  NOUN
NNP PROPN
NNPS  PROPN
NNS NOUN
PDT ADJ
POS PART
PRP PRON
PRP$  ADJ
RB  ADV
RBR ADV
RBS ADV
RP  PART
SYM SYM
TO  PART
UH  INTJ
VB  VERB
VBD VERB
VBG VERB
VBN VERB
VBP VERB
VBZ VERB
WDT ADJ
WP  NOUN
WP$ ADJ
WRB ADV
XX  X
_SP SPACE
``  PUNCT
POSSET
    trie = Aha::Cedar.new
    xposes = [] of String
    uposes = [] of String
    poses.each_line do |l|
      xpos, upos = l.split
      xposes << xpos.strip
      uposes << upos.strip
    end
    uposes.uniq!
    xposes.uniq!
    uposes = uposes - xposes
    xposes.each { |x| trie.insert x }
    uposes.each { |x| trie.insert x }
    xposes.each_with_index do |x, i|
      trie[i].should eq(x)
    end
    uposes.each_with_index { |x, i| trie[i + xposes.size].should eq(x) }
  end
end
