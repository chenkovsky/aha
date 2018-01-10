module Aha
  class SAM
    @lens : Array(Int32)
    @slinks : Array(Int32) # 不在同一个right class的最长的suffix的class
    @nmas : Array(Int32)   # nearest marked ancestor (NMA) data structure on the inverse suffix link tree
    @nexts : Array(Hash(Char, Int32))
    @flags : Array(UInt8)
    @outputs : Array(Int32) # outputs
    @key_lens : Array(Int32)

    private TRUNK_MASK = 1

    private def trunk?(sid)
      @flags[sid] & TRUNK_MASK
    end

    private def marked?(sid)
      @outputs[sid] >= 0
    end

    # 如果 -1， 则表示不存在
    private def nma(sid : Int32) : Int32
      return -1 if @nmas[sid] < 0
      if sid != @nmas[sid]
        @nmas[sid] = marked?(@nmas[sid]) ? @nmas[sid] : nma(@nmas[sid])
        return @nmas[sid]
      else
        return -1
      end
    end

    def self.compile(keys : Array(String)) : SAM
      sam = SAM.new
      keys.each do |key|
        sam << key
      end
      STDERR.puts "# after compile"
      STDERR.puts sam.to_dot
      return sam
    end

    def to_io(io : IO, format : IO::ByteFormat)
      Aha.array_to_io @lens, Int32, io, format
      Aha.array_to_io @slinks, Int32, io, format
      Aha.array_to_io @nmas, Int32, io, format
      Aha.array_to_io @flags, UInt8, io, format
      Aha.array_to_io @outputs, UInt32, io, format
      Aha.array_to_io @key_lens, UInt32, io, format
      @nexts.size.to_io io, format
      @nexts.each do |hs|
        Aha.hash_to_io hs, Char, Int32, io, format
      end
    end

    def self.from_io(io : IO, format : IO::ByteFormat) : self
      lens = Aha.array_from_io Int32, io, format
      slinks = Aha.array_from_io Int32, io, format
      nmas = Aha.array_from_io Int32, io, format
      flags = Aha.array_from_io UInt8, io, format
      outputs = Aha.array_from_io Int32, io, format
      key_lens = Aha.array_from_io Int32, io, format
      next_size = Int32.from_io io, format
      nexts = (0...next_size).map { |_| Aha.hash_from_io Char, Int32, io, format }
      return SAM.new(lens, slinks, nmas, nexts, flags, outputs, key_lens)
    end

    private def create_state(len : Int32 = 0, slink : Int32 = -1, next next_ = {} of Char => Int32, flag : UInt8 = 0_u8, nmas : Int32 = -2) : Int32
      sid = @lens.size
      @lens << len
      @slinks << slink
      if nmas == -2
        if slink == -1
          @nmas << sid
        else
          @nmas << slink
        end
      else
        @nmas << nmas
      end
      @nexts << next_
      @flags << flag
      @outputs << -1
      sid
    end

    def initialize(@lens, @slinks, @nmas, @nexts, @flags, @outputs, @key_lens)
    end

    def initialize
      @lens = [] of Int32
      @slinks = [] of Int32 # 不在同一个right class的最长的suffix的class
      @nmas = [] of Int32   # nearest marked ancestor (NMA) data structure on the inverse suffix link tree
      @nexts = [] of Hash(Char, Int32)
      @flags = [] of UInt8
      @outputs = [] of Int32
      @key_lens = [] of Int32
      create_state
    end

    def <<(key : String) : self
      insert key
      self
    end

    def insert(key : String) : Int32
      output = self[key]?
      return output if output
      last = 0
      key.each_char do |chr|
        last = sa_extend chr, last
      end
      id = @key_lens.size
      @outputs[last] = id
      @key_lens << key.size
      return id
    end

    def sa_extend(chr : Char, last : Int32)
      cur = create_state(@lens[last] + 1)
      p = last
      STDERR.puts "sa_extend: #{cur}"
      while p != -1 && !@nexts[p].has_key?(chr)
        @nexts[p][chr] = cur
        STDERR.puts "set @nexts[#{p}][#{chr}] = #{cur}"
        p = @slinks[p]
      end
      if p == -1
        @slinks[cur] = 0
        STDERR.puts "set @slinks[#{cur}] = 0"
      else
        q = @nexts[p][chr]
        if @lens[p] + 1 == @lens[q]
          @slinks[cur] = q
          STDERR.puts "[x] set slink: @slinks[#{cur}] = #{q}"
          @nmas[cur] = q
        else
          clone = create_state(@lens[p] + 1, @slinks[q], @nexts[q].clone, 0_u8, @nmas[q])
          while p != -1 && @nexts[p][chr] == q
            @nexts[p][chr] = clone
            STDERR.puts "set clone: @nexts[#{p}][#{chr}] = #{clone}"
            p = @slinks[p]
          end
          @nmas[q] = @nmas[cur] = @slinks[q] = @slinks[cur] = clone
          STDERR.puts "set slink: @slinks[#{q}] = @slinks[#{chr}] = #{clone}"
        end
      end
      cur
    end

    def save(path)
      File.open(path, "wb") do |f|
        to_io f, IO::ByteFormat::LittleEndian
      end
    end

    def self.load(path)
      File.open(path, "rb") do |f|
        return SAM.from_io f, IO::ByteFormat::LittleEndian
      end
    end

    def substr?(str) : Bool
      # str 是否是字典中的某个字符串的子串
      str.each_char do |chr|
        cur = 0
        key.each_char do |chr|
          n = @nexts[cur][chr]?
          return false if n.nil?
          cur = n
        end
      end
      return true
    end

    def match(str : String) : Int32?
      sid = 0
      str.each_char_with_index do |chr, idx|
        while !transition?(sid, chr) && sid != 0
          sid = @slinks[sid]
        end
        sid = @nexts[sid][chr] if transition?(sid, chr)
        sout = sid
        yield AC::Hit.new(idx + 1 - @key_lens[@outputs[sout]], idx + 1, @outputs[sout]) if marked?(sout)
        sout = nma(sout)
        while sout >= 0
          yield AC::Hit.new(idx + 1 - @key_lens[@outputs[sout]], idx + 1, @outputs[sout])
          sout = nma(sout)
        end
      end
    end

    def includes?(str : String) : Bool
      !self[str]?.nil?
    end

    # 精确匹配
    def []?(str : String) : Int32?
      sid = 0
      str.each_char_with_index do |chr, idx|
        return nil unless transition?(sid, chr)
        sid = @nexts[sid][chr]
      end
      return @outputs[sid] if marked?(sid)
      return nil
    end

    private def transition?(nid, chr) : Bool
      return false unless trunk?(nid)
      t = @nexts[nid][chr]?
      return false if t.nil?
      return false unless primary_edge?(nid, t)
      return false unless trunk?(t)
      return true
    end

    private def primary_edge?(nid, chl) : Bool
      @lens[chl] == @lens[nid] + 1
    end
  end
end
