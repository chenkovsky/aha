# require "bitarray"
# module Aha
#   class FlashText
#     @case_sensitive : Bool
#     @white_space_chars : BitArray
#     @non_word_boundaries : BitArray
#     @byte_map : Array(UInt8)
#     @trie : Cedar

#     def initialize(@case_sensitive : Bool = false)
#       @white_space_chars = BitArray.new(256)
#       ['.', '\t', '\n', '\a', ' ', ','].each do |chr|
#         @white_space_chars[chr.ord] = true
#       end
#       @non_word_boundaries = BitArray.new(256)
#       @byte_map = (0...256).map{|i| i.to_u8}
#       ('a'..'z').each{|chr| @non_word_boundaries[chr.ord] = true}
#       ('A'..'Z').each do|chr|
#         @non_word_boundaries[chr.ord] = true
#         unless @case_sensitive
#           @byte_map[chr.ord] = (chr.ord - 'A'.ord + 'a'.ord).to_u8
#         end
#       end
#       ('0'..'9').each{|chr| @non_word_boundaries[chr.ord] = true}
#     end
#     delegate :size, to: @trie

#     def includes?(key)
#       !self[key]?.nil?
#     end

#     def []?(key : String)
#       self[key.bytes]?
#     end

#     def []?(key : Bytes | Array(UInt8))
#       key = keys.map{|k| @byte_map[k]} unless @case_sensitive
#       @trie[key]?
#     end

#     def [](key : Bytes | String | Array(UInt8)) : Int32
#       ret = self[key]?
#       raise IndexError.new if ret.nil?
#       return ret
#     end

#     def insert(key : String)
#       insert key.bytes
#     end

#     def insert(key : Bytes| Array(UInt8))
#       key = keys.map{|k| @byte_map[k]} unless @case_sensitive
#       @trie.insert key
#     end

#     def delete(key : String)
#       delete key.bytes
#     end

#     def delete(key : Bytes| Array(UInt8))
#       key = keys.map{|k| @byte_map[k]} unless @case_sensitive
#       @trie.delete key
#     end

#   end
# end
