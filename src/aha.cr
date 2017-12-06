require "./aha/*"

class Aha
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
  getter :da

  def self.compile(keys : Array(String)) : Aha
    da = Cedar.new
    keys.each { |key| da.insert key }
    self.compile da
  end

  def self.compile(da : Cedar) : Aha
    nlen = da.array.size
    fails = Array(Int32).new(nlen, -1)
    output = Array(OutNode).new(nlen, OutNode.new(-1, -1))
    q = Deque(Cedar::NodeDesc).new
    ro = 0
    fails[ro] = ro
    da.childs(ro) do |c|
      fails[c.id] = ro
      q << c
    end
    while !q.empty?
      e = q.shift
      nid = e.id
      if da.is_end? nid
        vk = da.value nid
        output[nid].value = vk
      end
      da.childs nid do |c|
        q << c
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
          output[c.id].next = fid
        end
      end
    end
    return Aha.new(da, output, fails)
  end

  protected def initialize(@da, @output, @fails)
  end

  private def match_(seq : Bytes | Array(UInt8))
    nid = 0
    seq.each_with_index do |b, i|
      while true
        if @da.has_label? nid, b
          nid = da.child nid, b
          if da.is_end? nid
            yield i, nid
          end
          break
        end
        break if nid == 0
        nid = @fails[nid]
      end
    end
  end

  def match(str : String)
    # match str.bytes, &block
    match str.bytes do |hit|
      yield hit
    end
  end

  def match(seq : Bytes | Array(UInt8), &block)
    match_ seq do |idx, nid|
      e = @output.to_unsafe + nid
      while e.value.value >= 0
        val = e.value.value
        len = @da.key_len e.value.value
        yield Hit.new(idx - len + 1, idx + 1, val)
        e = @output.to_unsafe + e.value.next
      end
    end
  end
end
