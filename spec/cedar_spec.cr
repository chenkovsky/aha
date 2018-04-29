require "./spec_helper"

describe Aha do
  it "cedar insert delete" do
    trie = Aha::Cedar.new
    ids = %w(Ruby ruby rb).map do |s|
      trie.insert s
    end
    ids.should eq([0, 1, 2])
    trie.delete("ruby").should eq(1)
    trie.delete("ruby").should eq(-1)
    trie.insert("ruby").should eq(1)
  end
  it "cedar iter" do
    trie = Aha::Cedar.new(true)
    ids = %w(Ruby ruby rb XX).map do |s|
      trie.insert s
    end
    arr = [] of Tuple(String, Int32)
    trie.dfs_each { |k, v| arr << ({k, v}) }
    arr.should eq([{"Ruby", 0}, {"XX", 3}, {"rb", 2}, {"ruby", 1}])
    arr.clear
    trie.bfs_each { |k, v| arr << ({k, v}) }
    arr.should eq([{"XX", 3}, {"rb", 2}, {"Ruby", 0}, {"ruby", 1}])
    trie.to_a.map { |k, v| {k, v} }.should eq([{"Ruby", 0}, {"ruby", 1}, {"rb", 2}, {"XX", 3}])
  end

  it "words" do
    words = <<-TXT
Animacy_anim
Animacy_inam
Aspect_freq
Aspect_imp
Aspect_mod
Aspect_none
Aspect_perf
Case_abe
Case_abl
Case_abs
Case_acc
Case_ade
Case_all
Case_cau
Case_com
Case_dat
Case_del
Case_dis
Case_ela
Case_ess
Case_gen
Case_ill
Case_ine
Case_ins
Case_loc
Case_lat
Case_nom
Case_par
Case_sub
Case_sup
Case_tem
Case_ter
Case_tra
Case_voc
Definite_two
Definite_def
Definite_red
Definite_cons
Definite_ind
Degree_cmp
Degree_comp
Degree_none
Degree_pos
Degree_sup
Degree_abs
Degree_com
Degree_dim
Gender_com
Gender_fem
Gender_masc
Gender_neut
Mood_cnd
Mood_imp
Mood_ind
Mood_n
Mood_pot
Mood_sub
Mood_opt
Negative_neg
Negative_pos
Negative_yes
Polarity_neg
Polarity_pos
Number_com
Number_dual
Number_none
Number_plur
Number_sing
Number_ptan
Number_count
NumType_card
NumType_dist
NumType_frac
NumType_gen
NumType_mult
NumType_none
NumType_ord
NumType_sets
Person_one
Person_two
Person_three
Person_none
Poss_yes
PronType_advPart
PronType_art
PronType_default
PronType_dem
PronType_ind
PronType_int
PronType_neg
PronType_prs
PronType_rcp
PronType_rel
PronType_tot
PronType_clit
PronType_exc
Reflex_yes
Tense_fut
Tense_imp
Tense_past
Tense_pres
VerbForm_fin
VerbForm_ger
VerbForm_inf
VerbForm_none
VerbForm_part
VerbForm_partFut
VerbForm_partPast
VerbForm_partPres
VerbForm_sup
VerbForm_trans
VerbForm_conv
VerbForm_gdv
Voice_act
Voice_cau
Voice_pass
Voice_mid
Voice_int
Abbr_yes
AdpType_prep
AdpType_post
AdpType_voc
AdpType_comprep
AdpType_circ
AdvType_man
AdvType_loc
AdvType_tim
AdvType_deg
AdvType_cau
AdvType_mod
AdvType_sta
AdvType_ex
AdvType_adadj
ConjType_oper
ConjType_comp
Connegative_yes
Derivation_minen
Derivation_sti
Derivation_inen
Derivation_lainen
Derivation_ja
Derivation_ton
Derivation_vs
Derivation_ttain
Derivation_ttaa
Echo_rdp
Echo_ech
Foreign_foreign
Foreign_fscript
Foreign_tscript
Foreign_yes
Gender_dat_masc
Gender_dat_fem
Gender_erg_masc
Gender_erg_fem
Gender_psor_masc
Gender_psor_fem
Gender_psor_neut
Hyph_yes
InfForm_one
InfForm_two
InfForm_three
NameType_geo
NameType_prs
NameType_giv
NameType_sur
NameType_nat
NameType_com
NameType_pro
NameType_oth
NounType_com
NounType_prop
NounType_class
Number_abs_sing
Number_abs_plur
Number_dat_sing
Number_dat_plur
Number_erg_sing
Number_erg_plur
Number_psee_sing
Number_psee_plur
Number_psor_sing
Number_psor_plur
NumForm_digit
NumForm_roman
NumForm_word
NumValue_one
NumValue_two
NumValue_three
PartForm_pres
PartForm_past
PartForm_agt
PartForm_neg
PartType_mod
PartType_emp
PartType_res
PartType_inf
PartType_vbp
Person_abs_one
Person_abs_two
Person_abs_three
Person_dat_one
Person_dat_two
Person_dat_three
Person_erg_one
Person_erg_two
Person_erg_three
Person_psor_one
Person_psor_two
Person_psor_three
Polite_inf
Polite_pol
Polite_abs_inf
Polite_abs_pol
Polite_erg_inf
Polite_erg_pol
Polite_dat_inf
Polite_dat_pol
Prefix_yes
PrepCase_npr
PrepCase_pre
PunctSide_ini
PunctSide_fin
PunctType_peri
PunctType_qest
PunctType_excl
PunctType_quot
PunctType_brck
PunctType_comm
PunctType_colo
PunctType_semi
PunctType_dash
Style_arch
Style_rare
Style_poet
Style_norm
Style_coll
Style_vrnc
Style_sing
Style_expr
Style_derg
Style_vulg
Style_yes
StyleVariant_styleShort
StyleVariant_styleBound
VerbType_aux
VerbType_cop
VerbType_mod
VerbType_light
TXT
    trie = Aha::Cedar.new
    lines = [] of String
    words.each_line do |l|
      lines << l.strip
    end
    lines.each_with_index do |l, i|
      id = trie.insert l
    end
    trie.size.should eq(lines.size)
    lines.each_with_index do |x, i|
      trie[i].should eq(x)
      trie[x].should eq(i)
    end
  end
  it "prefix suffix" do
    trie = Aha::Cedar.new
    trie.insert "Polite_pol"
    trie.insert "polite"
    File.open("tmp.dot", "w") do |f|
      f.puts trie.to_dot
    end
    trie.to_dot
    arr = [] of String
    trie.prefix "Polite_pol", true do |k, _|
      arr << trie[k]
    end
    arr.should eq(["polite", "Polite_pol"])
    arr.clear
    trie.predict "Polite", true do |k, _|
      arr << trie[k]
    end
    arr.should eq(["polite", "Polite_pol"])
    arr.clear
    trie.exact "Polite", true do |k, _|
      arr << trie[k]
    end
    arr.should eq(["polite"])
  end
end
