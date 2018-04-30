module Aha
  struct Hit
    @start : Int32
    @end : Int32
    @value : Int32

    getter :start, :end, :value

    def initialize(@start, @end, @value)
    end
  end
  module MatchString

    private def char_map(seq)
      char_of_byte = Array(Int32).new(seq.bytesize)
      bytes = Array(UInt8).new(seq.bytesize)
      seq.each_char_with_index do |chr, chr_idx|
        chr.each_byte do |b|
          char_of_byte << chr_idx
          bytes << b
        end
      end
      return char_of_byte, bytes
    end
    def match(seq : String, &block)
      char_of_byte, bytes = char_map(seq)
      match(seq.bytes) do |hit|
        yield Hit.new(char_of_byte[hit.start], char_of_byte[hit.end-1] + 1, hit.value)
      end
    end

    def match(seq : String, sep : BitArray, &block)
      char_of_byte, bytes = char_map(seq)
      match(seq.bytes, sep) do |hit|
        yield Hit.new(char_of_byte[hit.start], char_of_byte[hit.end-1] + 1, hit.value)
      end
    end
  end
end
