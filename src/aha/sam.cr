module Aha
  class SAM
    struct State
      @len : Int32
      @link : Int32 # 不在同一个right class的最长的suffix的class
      @next : Hash(Char, Int32)

      def initialize(@len, @link = -1, @next = {} of Char => Int32)
      end

      def to_io(io : IO, format : IO::ByteFormat)
        @len.to_io io, format
        @link.to_io io, format
        @next.size.to_io io, format
        @next.each do |k, v|
          k.to_io io, format
          v.to_io io, format
        end
      end

      def self.from_io(io : IO, format : IO::ByteFormat) : self
        len = Int32.from_io io, format
        link = Int32.from_io io, format
        next_size = Int32.from_io io, format
        next_ = Hash(Char, Int32).new next_size
        (0...next_size).each do
          chr = Char.from_io io, format
          val = Int32.from_io io, format
          next_[chr] = val
        end
        return State.new(len, link, next_)
      end
    end

    def initialize
      @states = Array(State).new
      @states << State.new(0)
    end

    def <<(key : String)
      insert key
    end

    def insert(key : String)
      last = 0
      key.each_char do |chr|
        last = sa_extend chr, last
      end
    end

    def sa_extend(chr : Char, last : Int32)
      cur = @states.size
      @states << State.new(Aha.at(@states, last).len + 1)
      p = last
      while p != -1 && !Aha.at(@states, p).next.key?(chr)
        Aha.at(@states, p).next[chr] = cur
        p = Aha.at(@states, p).link
      end
      if p == -1
        Aha.at(@states, cur).link = 0
      else
        q = Aha.at(@states, p).next[c]
        if Aha.at(@states, p).len + 1 == Aha.at(@states, q).len
          Aha.at(@states, cur).link = q
        else
          clone = @states.size
          @states << State.new(Aha.at(@states, p).len + 1, Aha.at(@states, q).link, Aha.at(@states, q).next.clone)
          while p != -1 && Aha.at(@states, p).next[c] == q
            Aha.at(@states, p).next[c] = clone
            p = Aha.at(@states, p).link
          end
          Aha.at(@states, q).link = Aha.at(@states, cur).link = clone
        end
      end
      cur
    end

    def to_io(io : IO, format : IO::ByteFormat)
      array_to_io @states, io, format
    end

    def from_io(io : IO, format : IO::ByteFormat) : self
      array_from_io @states, State, io, format
    end

    def save(path)
      File.open(path, "wb") do |f|
        to_io f, IO::ByteFormat::LittleEndian
      end
    end

    def self.load(path)
      sam = SAM.new
      File.open(path, "rb") do |f|
        sam.from_io f, IO::ByteFormat::LittleEndian
      end
      sam
    end
  end
end
