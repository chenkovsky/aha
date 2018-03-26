module Aha
  # an open address hash table
  class ArrayHash(N) # N is the byte num of value

    include Enumerable({Bytes, Bytes})
    alias Slot = UInt8*

    @n : UInt64     # number of slots
    @m : UInt64     # number of key/value pairs stored
    @max_m : UInt64 # number of stored keys before we resize
    @slot_sizes : UInt64*
    @slots : Slot*
    MAX_LOAD_FACTOR = 100000.0
    INITIAL_SIZE    = 4096_u64

    # key长的用两个字节表示长度，key短的用一个字节表示长度
    protected def self.key_len(s : Slot) : UInt64
      return (s.value >> 1).to_u64 if (0x1 & s.value) != 0
      return (s[0] + (s[1] << 8)).to_u64 >> 1
    end

    def to_io(io : IO, format : IO::ByteFormat)
      @n.to_io io, format
      @m.to_io io, format
      @max_m.to_io io, format

      (0...@n).each { |i| @slot_sizes[i].to_io io, format }

      total_size = 0
      (0...@n).each do |i|
        slot_size = @slot_sizes[i]
        total_size += slot_size
        (0...slot_size).each do |s|
          @slots[i][s].to_io io, format
        end
      end
      padding = 4 - (total_size % 4)
      if padding != 4
        (0...padding).each { |_| 0_u8.to_io io, format }
      end
    end

    def self.from_io(io : IO, format : IO::ByteFormat)
      n = UInt64.from_io io, format
      m = UInt64.from_io io, format
      max_m = UInt64.from_io io, format

      slot_sizes = Pointer(UInt64).malloc(n)
      (0...n).each { |i| slot_sizes[i] = UInt64.from_io io, format }

      total_size = 0
      slots = (0...n).map do |i|
        slot_size = slot_sizes[i]
        if slot_size > 0
          slot = Slot.malloc(slot_size)
          total_size += slot_size
          (0...slot_size).each do |j|
            slot[j] = UInt8.from_io io, format
          end
          slot
        else
          Slot.null
        end
      end
      padding = 4 - (total_size % 4)
      if padding != 4
        (0...padding).each { |_| UInt8.from_io io, format }
      end
      return self.new(n, m, max_m, slot_sizes, slots.to_unsafe)
    end

    def initialize(@n, @m, @max_m, @slot_sizes, @slots)
    end

    def initialize(@n = INITIAL_SIZE)
      @m = 0_u64
      @max_m = (MAX_LOAD_FACTOR * @n).to_u64
      @slots = Pointer(Slot).malloc(@n, Slot.null)
      @slot_sizes = Pointer(UInt64).malloc(@n, 0_u64)
    end

    def clear
      @n = INITIAL_SIZE
      @slots = Pointer(Slot).malloc(@n, Slot.null)
      @slot_sizes = Pointer(UInt64).malloc(@n, 0_u64)
    end

    def sizeof
      nbytes = sizeof(ArrayHash) + @n * (sizeof(UInt64) + sizeof(Slot))
      (0...@n).reduce(nbytes) { |acc, cur| acc += @slot_sizes[cur] }
    end

    # Number of stored keys.
    def size
      @m
    end

    # 存储
    # key 后面紧跟 value
    # val 用来储存 value的指针
    # 返回结尾的指针
    private def ins_key(s : Slot, key : Bytes | Array(UInt8), val : UInt8**) : Slot
      size = key.size
      if size < 128
        s[0] = (size << 1).to_u8
        s += 1
      else
        len = ((size << 1) | 0x1).to_u16
        s[0] = (len & 255).to_u8
        s[1] = (len >> 8).to_u8
        s += 2
      end

      # key
      s.copy_from key.to_unsafe, size
      s += size
      val.value = s
      s += N
      return s
    end

    private def expand
      # Resizing a table is essentially building a brand new one.
      # One little shortcut we can take on the memory allocation front is to
      # figure out how much memory each slot needs in advance.
      new_n = @n << 1
      slot_sizes = Pointer(UInt64).malloc(new_n, 0_u64)

      each do |k, v|
        slot_sizes[(k.hash) % new_n] += k.size + N + (k.size >= 128 ? 2 : 1)
      end
      slots = Pointer(Slot).malloc(new_n)
      (0...new_n).each do |j|
        if slot_sizes[j] > 0
          slots[j] = Slot.malloc(slot_sizes[j])
        else
          slots[j] = Slot.null
        end
      end
      # slots_next 用来存储所有的slot的结尾的指针
      slots_next = Pointer(Slot).malloc(new_n)
      slots_next.copy_from(slots, new_n)
      h = 0_u64
      u = Pointer(UInt8).null
      each do |k, v|
        h = (k.hash) % new_n
        slots_next[h] = ins_key(slots_next[h], k, pointerof(u))
        v.copy_to(u, v.size)
      end
      @slots = slots
      @slot_sizes = slot_sizes
      @n = new_n
      @max_m = (MAX_LOAD_FACTOR * @n).to_u64
    end

    private def get_key(key : Bytes | Array(UInt8), insert_missing : Bool) : UInt8*
      expand if insert_missing && @m >= @max_m
      len = key.size
      i = (key.hash) % @n
      s_start = s = @slots[i]
      slot_size = @slot_sizes[i]
      val = Pointer(UInt8).null

      # 尝试查找该key
      while (s - s_start) < slot_size
        k = self.class.key_len s
        s += k < 128 ? 1 : 2
        # skip keys that are longer than ours
        if k != len
          s += k + N
          next
        end
        return (s + len).as(UInt8*) if s.memcmp(key.to_unsafe, len) == 0 # key found
        s += k + N
        next
      end
      # 没有找到
      if insert_missing
        new_size = @slot_sizes[i]
        new_size += 1 + (len >= 128 ? 1 : 0)
        new_size += len
        new_size += N
        @slots[i] = @slots[i].realloc(new_size)
        @m += 1
        ins_key(@slots[i] + @slot_sizes[i], key, pointerof(val))
        @slot_sizes[i] = new_size
        return val
      end
      return Pointer(UInt8).null
    end

    def get(key : Bytes | Array(UInt8))
      if key.size > 32767
        raise "HAT-trie/AH-table cannot store keys longer than 32768"
      end
      return get_key key, true
    end

    def []=(key : String, val)
      self[Bytes.new key.to_unsafe, key.bytesize] = val
    end

    def []=(key : Bytes | Array(UInt8), val : Bytes | Array(UInt8))
      val_ptr = get key
      min_size = val.size > N ? N : val.size
      (0...min_size).each do |i|
        val_ptr[i] = val[i]
      end
      self
    end

    def [](key : String)
      self[Bytes.new key.to_unsafe, key.bytesize]
    end

    def []?(key : String)
      self[Bytes.new key.to_unsafe, key.bytesize]?
    end

    def delete(key : String)
      delete Bytes.new(key.to_unsafe, key.bytesize)
    end

    def []?(key : Bytes | Array(UInt8)) : Bytes?
      val_ptr = try_get key
      return nil if val_ptr == Pointer(UInt8).null
      return Bytes.new(N) { |i| val_ptr[i] }
    end

    def [](key : Bytes | Array(UInt8)) : Bytes
      ret = self[key]?
      raise IndexError.new if ret.nil?
      return ret
    end

    def try_get(key : Bytes | Array(UInt8)) : UInt8*
      get_key(key, false)
    end

    def delete(key : Bytes | Array(UInt8)) : Bool
      i = key.hash % @n
      s_start = s = @slots[i]
      slot_size = @slot_sizes[i]
      while (s - s_start) < slot_size
        k = self.class.key_len s
        s += k < 128 ? 1 : 2
        if k != key.size
          s += k + N
          next
        end
        if s.memcmp(key.to_unsafe, key.size) == 0
          # 找到了当前的key
          t = s + key.size + N
          s -= k < 128 ? 1 : 2
          s.move_from(t, slot_size - (t - s_start))
          @slot_sizes[i] -= t - s
          @m -= 1
          return true
        end
        s += k + N
        next
      end
      return false
    end

    def each(sorted : Bool)
      if sorted
        arr = [] of {Bytes, Bytes}
        each do |kv|
          arr << kv
        end
        arr.sort! do |e1, e2|
          Aha.bytes_cmp(e1[0], e2[0])
        end
        arr.each do |kv|
          yield kv
        end
      else
        each do |kv|
          yield kv
        end
      end
    end

    def each
      (0...@n).each do |idx|
        slot = @slots[idx]
        s_start = s = @slots[idx]
        slot_size = @slot_sizes[idx]
        while (s - s_start) < slot_size
          k = self.class.key_len s
          s += k < 128 ? 1 : 2
          key = Bytes.new(s, k)
          s += k
          val = s.as(UInt8*)
          s += N
          yield({key, Bytes.new(val, N)})
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
        return self.from_io f, Aha::ByteFormat
      end
    end
  end
end
