require "./aha/*"

class Aha
  # 如果找不到子节点，每次都去fail节点查看有没有相对应的子节点。
  # 相应的，如果找到了end节点，也需要将fail节点的out values加入

  struct Hit
    @start : Int32
    @end : Int32
    @value : Int32

    getter :start, :end, :value

    def initialize(@start, @end, @value)
    end
  end

  struct OutNode
    @next : Int32
    @value : Int32
    property :value, :next

    def initialize(@next, @value)
    end
  end

  @da : Cedar
  @output : Array(OutNode)
  @fails : Array(Int32)
  @key_lens : Array(Int32)

  def self.compile(keys : Array(String) | Array(Array(UInt8))) : Aha
    da = Cedar.new
    keys.each { |key| da.insert key }
    self.compile da
  end

  alias NodeDesc = NamedTuple(node: Cedar::NodeDesc, len: Int32)

  def self.compile(da : Cedar) : Aha
    nlen = da.array.size
    fails = Array(Int32).new(nlen, -1)
    output = Array(OutNode).new(nlen, OutNode.new(-1, -1))
    q = Deque(NodeDesc).new
    key_lens = Array(Int32).new(da.key_num, 0)
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
        key_lens[vk] = l
        Cedar.at(output, nid).value = vk
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
          Cedar.at(output, c.id).next = fid
        end
      end
    end
    return Aha.new(da, output, fails, key_lens)
  end

  protected def initialize(@da, @output, @fails, @key_lens)
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

  private def byte_index_to_char_index(seq : String)
    start_byte_idx = 0
    ret = {} of Int32 => Int32
    seq.each_char_with_index do |chr, idx|
      ret[start_byte_idx] = idx
      start_byte_idx += chr.bytesize
    end
    ret[start_byte_idx] = seq.size
    return ret
  end

  private def byte_index_to_char_index(seq : Array(UInt8))
    byte_index_to_char_index seq.to_unsafe
  end

  private def byte_index_to_char_index(seq : Bytes)
    byte_index_to_char_index String.new(seq)
  end

  def match(seq : String | Bytes | Array(UInt8), bytewise : Bool = false, &block)
    seq_ = seq.is_a?(String) ? seq.bytes : seq
    offset_mapping = bytewise ? nil : byte_index_to_char_index(seq)
    match_ seq_ do |idx, nid|
      e = Cedar.pointer @output, nid
      while e.value.value >= 0
        val = e.value.value
        len = @key_lens[val]
        start_offset = idx - len + 1
        end_offset = idx + 1
        unless bytewise
          start_offset = offset_mapping.not_nil![start_offset]
          end_offset = offset_mapping.not_nil![end_offset]
        end
        yield Hit.new(start_offset, end_offset, val)
        break unless e.value.next >= 0
        e = Cedar.pointer(@output, e.value.next)
      end
    end
  end
end
