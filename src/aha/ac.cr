require "./matcher"
require "bit_array"
require "super_io"

module Aha
  # 如果找不到子节点，每次都去fail节点查看有没有相对应的子节点。
  # 相应的，如果找到了end节点，也需要将fail节点的out values加入
  alias AC = ACX(Int32)
  alias ACBig = ACX(Int64)

  class ACX(T)
    include Aha::MatchString
    SuperIO.save_load

    struct OutNode(T)
      @next : T
      @value : T
      property :value, :next

      def initialize(@next, @value)
      end

      def to_io(io : IO, format : IO::ByteFormat)
        @next.to_io io, format
        @value.to_io io, format
      end

      def self.from_io(io : IO, format : IO::ByteFormat) : self
        next_ = T.from_io io, format
        value = T.from_io io, format
        return OutNode(T).new(next_, value)
      end
    end

    @da : CedarX(T)
    @output : ArrayX(OutNode(T))
    @fails : ArrayX(T)
    @key_lens : ArrayX(UInt32)
    @del_num : T

    delegate :[], to: @da
    delegate :[]?, to: @da

    def to_io(io : IO, format : IO::ByteFormat)
      @da.to_io io, format
      @output.to_io io, format
      @fails.to_io io, format
      @key_lens.to_io io, format
      @del_num.to_io io, format
    end

    def self.from_io(io : IO, format : IO::ByteFormat) : self
      da = CedarX(T).from_io io, format
      output = ArrayX(OutNode(T)).from_io io, format
      fails = ArrayX(T).from_io io, format
      key_lens = ArrayX(UInt32).from_io io, format
      del_num = T.from_io io, format
      ACX(T).new(da, output, fails, key_lens, del_num)
    end

    def self.compile(keys : Array(String) | Array(Array(UInt8)) | Array(Bytes)) : self
      da = CedarX(T).new
      keys.each_with_index do |key, idx|
        kid = da.insert key
        raise "key:#{key} appear twice." if kid != idx
      end
      self.compile da
    end

    def self.compile(da : CedarX(T)) : self
      nlen = da.array_size
      fails = ArrayX(T).new(nlen, T.new(-1))
      output = ArrayX(OutNode(T)).new(nlen, OutNode(T).new(T.new(-1), T.new(-1)))
      q = Deque(NamedTuple(node: Cedar::NodeDesc(T), len: Int32)).new
      key_lens = ArrayX(UInt32).new(da.leaf_size, 0_u32)
      ro = T.new(0)
      fails[ro] = ro
      da.children(ro) do |c|
        # 根节点的子节点，失败都返回根节点
        fails[c.id] = ro
        q << ({node: c, len: 1})
      end
      while !q.empty?
        n = q.shift
        e = n[:node]
        l = n[:len]
        nid = e.id
        if da.is_end? nid
          vk = da.value nid
          key_lens[vk] = l.to_u32
          Aha.at(output, nid).value = vk
        end
        da.children nid do |c|
          q << ({node: c, len: l + 1})
          fid = nid
          while fid != ro
            fs = fails[fid]
            if da.has_label? fs, c.label
              fid = da.child fs, c.label
              break
            end
            fid = fails[fid]
          end
          fails[c.id] = fid
          if da.is_end? fid
            Aha.at(output, c.id).next = fid
          end
        end
      end
      return self.new(da, output, fails, key_lens)
    end

    protected def initialize(@da, @output, @fails, @key_lens, @del_num = T.new(0))
    end

    private def match_(seq : Bytes | Array(UInt8))
      nid = T.new(0)
      seq.each_with_index do |b, i|
        while true
          nid_ = @da.child nid, b
          if nid_ >= 0
            nid = nid_
            if @da.is_end? nid
              yield i, nid
            end
            break
          end
          break if nid == 0
          nid = @fails[nid]
        end
      end
    end

    private def match_(seq : String, char_of_byte : Array(Int32))
      nid = 0
      seq.each_char_with_index do |chr, i|
        chr.each_byte do |b|
          char_of_byte << i
          while true
            nid_ = @da.child nid, b
            if nid_ >= 0
              nid = nid_
              if @da.is_end? nid
                yield (char_of_byte.size - 1), nid
              end
              break
            end
            break if nid == 0
            nid = @fails[nid]
          end
        end
      end
    end

    private KEY_LEN_MASK = ~(1 << 31)
    private DELETE_MASK  = (1 << 31)

    def size
      @key_lens - @del_num
    end

    def delete(kid : T)
      @del_num += 1 if (@key_lens[kid] & DELETE_MASK) == 0
      @key_lens[kid] ||= DELETE_MASK
    end

    private def fetch(idx, nid)
      e = Aha.pointer @output, nid
      while e.value.value >= 0
        val = e.value.value
        if @key_lens[val] < KEY_LEN_MASK
          len = @key_lens[val] & (KEY_LEN_MASK)
          start_offset = idx - len + 1
          end_offset = idx + 1
          yield Hit.new(start_offset, end_offset, val.to_i32)
        end
        break unless e.value.next >= 0
        e = Aha.pointer(@output, e.value.next)
      end
    end

    def match(seq : Bytes | Array(UInt8), &block)
      match_ seq do |idx, nid|
        fetch(idx, nid) do |hit|
          yield hit
        end
      end
    end

    def match(seq : Bytes | Array(UInt8), sep : BitArray, &block)
      raise "sep BitArray size > 256 is not supported" if sep.size > 256
      match_ seq do |idx, nid|
        if idx + 1 < seq.size
          chr = seq[idx + 1]
          if chr < sep.size && !sep[chr]
            next
          end
        end
        fetch(idx, nid) do |hit|
          if hit.start > 0
            chr = seq[hit.start - 1]
            if chr < sep.size && !sep[chr]
              next
            end
          end
          yield hit
        end
      end
    end
  end
end
