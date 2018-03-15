module Aha
  # 用于存储单调递增的整数序列, 能够对序列进行压缩
  struct EliasFano(T)
    @bytes : UInt8*
    @length : UInt64
    @u : T

    def self.round_up(val : UInt64, den : UInt64) : UInt64
      val = val == 0 ? den : val
      return (val % den == 0) ? val : val + (den - (val % den))
    end

    # Returns the number of lower bits required to encode each element in an
    # array of size length with maximum value u
    def self.get_l(u : UInt32, length : UInt32)
      x = round_up(u.to_u64, length.to_u64) / length
      return (sizeof(T) << 3) - Aha.leading_zero(x - 1)
    end

    def initialize(ptr : T*, @length : UInt64)
      @u = ptr[length - 1]
      l = self.class.get_l u, length
      @bytes = Pointer(UInt8).malloc(compressed_size(@u, @length))
      low_bits_offset = 0
      high_bits_offset = round_up l * @length, 8
      prev = 0
      (0...@length).each do |i|
        # @TODO
      end
    end

    def [](idx : UInt64) : T
    end

    def self.compressed_size(u, length)
      l = get_l u, length
      num_low_bits = round_up l * length, 8
      num_high_bits = round_up 2 * length, 8
      (num_low_bits + num_high_bits) / 8
    end
  end
end
