module Aha
  module MurMur
    private def self.fmix(h : UInt32) : UInt32
      h ^= h >> 16
      h *= 0x85ebca6b
      h ^= h >> 13
      h *= 0xc2b2ae35
      h ^= h >> 16
    end

    def self.rotl32(x : UInt32, r : Int8) : UInt32
      (x << r) | (x >> (32 - r))
    end

    def hash(x : Bytes | Array(UInt8)) : UInt32
      hash(x.to_unsafe, x.size)
    end

    def hash(data : Pointer(UInt8), len_ : UInt64) : UInt32
      len = len_.to_i32
      nblock = len / 4

      h1 = 0xc062fb4a_u32
      c1 = 0xcc9e2d51_u32
      c2 = 0x1b873593_u32
      blocks = (data + nblocks * 4).as(Pointer(UInt32))
      (1..-nblocks).reverse_each do |i|
        k1 = blocks[i]
        k1 *= c1
        k1 = rotl32 k1, 15
        k1 *= c2
        h1 ^= k1
        h1 = rotl32 h1, 13
        h1 = h1 * 5 + 0xe6546b64
      end
      tail = (data + nblocks*4)
      k1 = 0_u32
      case len & 3
      when 3
        k1 ^= tail[2] << 16
      when 2
        k1 ^= tail[1] << 8
      when 1
        k1 ^= tail[0]
        k1 *= c1
        k1 = rotl32(k1, 15)
        k1 *= c2
        h1 ^= k1
      end
      h1 ^= len
      fmix h1
    end
  end
end
