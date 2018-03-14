module Aha
  # 如果找不到子节点，每次都去fail节点查看有没有相对应的子节点。
  # 相应的，如果找到了end节点，也需要将fail节点的out values加入
  class AC
    struct OutNode
      @next : Int32
      @value : Int32
      property :value, :next

      def initialize(@next, @value)
      end

      def to_io(io : IO, format : IO::ByteFormat)
        @next.to_io io, format
        @value.to_io io, format
      end

      def self.from_io(io : IO, format : IO::ByteFormat) : self
        next_ = Int32.from_io io, format
        value = Int32.from_io io, format
        return OutNode.new(next_, value)
      end
    end

    @da : Cedar
    @output : Array(OutNode)
    @fails : Array(Int32)
    @key_lens : Array(UInt32)
    @del_num : Int32

    delegate :[], to: @da
    delegate :[]?, to: @da

    def to_io(io : IO, format : IO::ByteFormat)
      @da.to_io io, format
      Aha.array_to_io @output, OutNode, io, format
      Aha.array_to_io @fails, Int32, io, format
      Aha.array_to_io @key_lens, UInt32, io, format
      @del_num.to_io io, format
    end

    def self.from_io(io : IO, format : IO::ByteFormat) : AC
      da = Cedar.from_io io, format
      output = Aha.array_from_io OutNode, io, format
      fails = Aha.array_from_io Int32, io, format
      key_lens = Aha.array_from_io UInt32, io, format
      del_num = Int32.from_io io, format
      AC.new(da, output, fails, key_lens, del_num)
    end

    def self.compile(keys : Array(String) | Array(Array(UInt8)) | Array(Bytes)) : AC
      da = Cedar.new
      keys.each_with_index do |key, idx|
        kid = da.insert key
        raise "key:#{key} appear twice." if kid != idx
      end
      self.compile da
    end

    alias NodeDesc = NamedTuple(node: Cedar::NodeDesc, len: Int32)

    def self.compile(da : Cedar) : AC
      nlen = da.array.size
      fails = Array(Int32).new(nlen, -1)
      output = Array(OutNode).new(nlen, OutNode.new(-1, -1))
      q = Deque(NodeDesc).new
      key_lens = Array(UInt32).new(da.key_num, 0_u32)
      ro = 0
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
      return AC.new(da, output, fails, key_lens)
    end

    protected def initialize(@da, @output, @fails, @key_lens, @del_num = 0)
    end

    private def match_(seq : Bytes | Array(UInt8))
      nid = 0
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

    private def byte_index_to_char_index(seq : Array(UInt8))
      byte_index_to_char_index seq.to_unsafe
    end

    private def byte_index_to_char_index(seq : Bytes)
      byte_index_to_char_index String.new(seq)
    end

    private KEY_LEN_MASK = ~(1 << 31)
    private DELETE_MASK  = (1 << 31)

    def size
      @key_lens - @del_num
    end

    def delete(kid : Int32)
      @del_num += 1 if (@key_lens[kid] & DELETE_MASK) == 0
      @key_lens[kid] ||= DELETE_MASK
    end

    def match(seq : String | Bytes | Array(UInt8), bytewise : Bool = false, &block)
      seq_ = seq.is_a?(String) ? seq.bytes : seq
      offset_mapping = bytewise ? nil : Aha.byte_index_to_char_index(seq)
      match_ seq_ do |idx, nid|
        e = Aha.pointer @output, nid
        while e.value.value >= 0
          val = e.value.value
          if @key_lens[val] < KEY_LEN_MASK
            len = @key_lens[val] & (~(1 << 31))
            start_offset = idx - len + 1
            end_offset = idx + 1
            unless bytewise
              start_offset = offset_mapping.not_nil![start_offset]
              end_offset = offset_mapping.not_nil![end_offset]
            end
            yield Hit.new(start_offset, end_offset, val)
          end
          break unless e.value.next >= 0
          e = Aha.pointer(@output, e.value.next)
        end
      end
    end

    def save(path)
      File.open(path, "wb") do |f|
        to_io f, Aha::ByteFormat
      end
    end

    def self.load(path)
      File.open(path, "rb") do |f|
        return AC.from_io f, Aha::ByteFormat
      end
    end
  end
end
