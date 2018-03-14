require "sub_hash"

struct SubHash
  def to_io(io, format, include_cache = false)
    @modulo.to_io io, format
    @base.to_io io, format
    if include_cache
      Aha.array_to_io @power_cache, UInt64, io, format
    end
  end

  def self.from_io(io, format, include_cache = false)
    modulo = UInt64.from_io io, format
    base = UInt64.from_io io, format
    if include_cache
      power_cache = Aha.array_from_io UInt64, io, format
      return SubHash.new(base, modulo, power_cache)
    else
      return SubHash.new(base, modulo)
    end
  end

  def initialize(@base, @modulo, @power_cache)
    @suffix_cache = Array(UInt64).new(@power_cache.size, 0_u64)
    @term_size = 0
  end
end

module Aha
  class WuManber
    @[Flags]
    enum CharSet
      Alphabet
      Number
      Other
    end

    DefaultB       = 3
    DefaultCharSet = CharSet::Alphabet | CharSet::Number | CharSet::Other

    OtherChars = (0...256).map { |t| true }
    OtherChars[' '.ord] = false
    ('a'..'z').each { |chr| OtherChars[chr.ord] = false }
    ('A'..'Z').each { |chr| OtherChars[chr.ord] = false }
    ('0'..'9').each { |chr| OtherChars[chr.ord] = false }

    struct Alphabet
      @byte : UInt8
      @offset : UInt8
      getter :letter, :offset

      def initialize(@byte, @offset)
      end

      def to_io(io, format)
        @byte.to_io io, format
        @offset.to_io io, format
      end

      def self.from_io(io : IO, format : IO::ByteFormat) : self
        byte = UInt8.from_io io, format
        offset = UInt8.from_io io, format
        return Alphabet.new(byte, offset)
      end
    end

    @alphabet : Array(Alphabet)
    @patterns : Array(Bytes)
    @b : Int32
    @min_len : Int32 # min pattern size
    @size_of_alphabet : Int32
    @bits_in_shift : Int32
    @shift_table : Array(Int32)
    @pattern_lens : Hash(Int32, Array(Int32))  # hash值到所有可能的长度
    @pattern_maps : Hash(UInt32, Array(Int32)) # 整个字符串进行hash作为key
    @hasher : SubHash

    def self.compile(patterns : Array(String) | Array(Slice), b = DefaultB,
                     case_sensitive = false,
                     byte_set = DefaultCharSet,
                     hasher = SubHash.new)
      pattern_ = if patterns.is_a? Array(String)
                   patterns.map { |x| x.encode("utf8") }
                 else
                   patterns
                 end
      self.new(pattern_, b, case_sensitive, byte_set, hasher)
    end

    def to_io(io, format)
      @hasher.to_io io, format
      Aha.array_to_io @alphabet, Alphabet, io, format
      @patterns.size.to_io io, format
      @patterns.each do |p|
        p.size.to_io io, format
        io.write p
      end
      @b.to_io io, format
      @min_len.to_io io, format
      @size_of_alphabet.to_io io, format
      @bits_in_shift.to_io io, format
      Aha.array_to_io @shift_table, Int32, io, format
      @pattern_lens.size.to_io io, format
      @pattern_lens.each { |k, _| k.to_io io, format }
      @pattern_lens.each { |_, v| Aha.array_to_io v, Int32, io, format }

      @pattern_maps.size.to_io io, format
      @pattern_maps.each { |k, _| k.to_io io, format }
      @pattern_maps.each { |_, v| Aha.array_to_io v, Int32, io, format }
    end

    def self.from_io(io, format)
      hasher = SubHash.from_io io, format
      alphabet = Aha.array_from_io Alphabet, io, format
      patterns_size = Int32.from_io io, format
      patterns = (0...patterns_size).map do |_|
        pat_size = Int32.from_io io, format
        slice = Bytes.new(pat_size)
        io.read slice
        slice
      end
      b = Int32.from_io io, format
      min_len = Int32.from_io io, format
      size_of_alphabet = Int32.from_io io, format
      bits_in_shift = Int32.from_io io, format
      shift_table = Aha.array_from_io Int32, io, format

      pattern_len_size = Int32.from_io io, format
      ks = (0...pattern_len_size).map { |_| Int32.from_io io, format }
      vs = (0...pattern_len_size).map { |_| Aha.array_from_io Int32, io, format }
      pattern_lens = Hash(Int32, Array(Int32)).zip(ks, vs)
      pattern_map_size = Int32.from_io io, format
      ks2 = (0...pattern_map_size).map { |_| UInt32.from_io io, format }
      vs2 = (0...pattern_map_size).map { |_| Aha.array_from_io Int32, io, format }
      pattern_maps = Hash(UInt32, Array(Int32)).zip(ks2, vs2)
      return WuManber.new(hasher, alphabet, patterns, b, min_len, size_of_alphabet, shift_table, pattern_lens, pattern_maps, bits_in_shift)
    end

    def initialize(@hasher, @alphabet, @patterns, @b, @min_len, @size_of_alphabet, @shift_table, @pattern_lens, @pattern_maps, @bits_in_shift)
    end

    def initialize(@patterns, @b = DefaultB,
                   case_sensitive = false,
                   byte_set = DefaultCharSet, @hasher = SubHash.new)
      @min_len = @patterns.min_of { |p| p.size }
      @alphabet = Array(Alphabet).new(256, Alphabet.new(' '.ord.to_u8, 0_u8))
      @size_of_alphabet = 1 # at minimum we have a white space character
      if byte_set.alphabet?
        ('a'..'z').each do |chr|
          @alphabet[chr.ord] = Alphabet.new(chr.ord.to_u8, @size_of_alphabet.to_u8)
          @size_of_alphabet += 1
        end
        if case_sensitive
          ('A'..'Z').each do |chr|
            @alphabet[chr.ord] = Alphabet.new(chr.ord.to_u8, @size_of_alphabet.to_u8)
            @size_of_alphabet += 1
          end
        end
      end
      if byte_set.number?
        ('0'..'9').each do |chr|
          @alphabet[chr.ord] = Alphabet.new(chr.ord.to_u8, @size_of_alphabet.to_u8)
          @size_of_alphabet += 1
        end
      end
      if !case_sensitive && byte_set.alphabet?
        ('A'..'Z').each do |chr|
          letter = ('a' + (chr - 'A')).ord.to_u8
          @alphabet[chr.ord] = Alphabet.new(letter, @alphabet[letter].offset)
        end
      end
      if byte_set.other?
        OtherChars.each_with_index do |is_other, chr|
          next unless is_other
          @alphabet[chr] = Alphabet.new(chr.to_u8, @size_of_alphabet.to_u8)
          @size_of_alphabet += 1
        end
      end
      @bits_in_shift = Aha.msb_for_2power Math.pw2ceil(@size_of_alphabet).to_u32
      table_size = (1 << @bits_in_shift) ** @b
      @shift_table = Array(Int32).new(table_size, @min_len - @b + 1)
      @pattern_lens = Hash(Int32, Array(Int32)).new
      @pattern_maps = Hash(UInt32, Array(Int32)).new
      @patterns.each_with_index do |pat, j|
        full_hash = SubHash.hash pat
        (@b..@min_len).reverse_each do |q|
          hs = (0...@b).reverse_each.reduce(0) { |acc, i| (acc << @bits_in_shift) + @alphabet[pat[q - i - 1]].offset }
          shift_len = @min_len - q
          @shift_table[hs] = shift_len if shift_len < @shift_table[hs]
          if shift_len == 0
            arr = @pattern_lens[hs] ||= [] of Int32
            Aha.ordered_insert arr, pat.size
            arr = @pattern_maps[full_hash.to_u32] ||= [] of Int32
            arr << j
          end
        end
      end
    end

    def match(text : Bytes | String | Array(Bytes), bytewise : Bool = false, &block)
      text_ = text.is_a?(String) ? text.bytes : text
      offset_mapping = bytewise ? nil : Aha.byte_index_to_char_index(text)
      @hasher.sub_hash text_
      ix = @min_len - 1
      while ix < text_.size
        hs1 = (0...@b).reverse_each.reduce(0) { |acc, i| (acc << @bits_in_shift) + @alphabet[text_[ix - i]].offset }
        shift = @shift_table[hs1]
        if shift > 0
          ix += shift
          next
        end
        @pattern_lens[hs1].each do |len|
          start_idx = ix - @min_len + 1
          next if len + start_idx > text_.size
          arr = @pattern_maps[@hasher[start_idx, len].to_u32]?
          next unless arr
          arr.each do |pat_idx|
            if @patterns[pat_idx].size == len && (0...len).all? { |i| @patterns[pat_idx][i] == text_[start_idx + i] }
              end_idx = start_idx + len
              unless bytewise
                start_idx = offset_mapping.not_nil![start_idx]
                end_idx = offset_mapping.not_nil![end_idx]
              end
              yield Hit.new(start_idx, end_idx, pat_idx)
            end
          end
        end
        ix += 1
      end
    end

    def save(path)
      File.open(path, "wb") do |f|
        to_io f, Aha::ByteFormat
      end
    end

    def self.load(path)
      File.open(path, "rb") do |f|
        return WuManber.from_io f, Aha::ByteFormat
      end
    end
  end
end
