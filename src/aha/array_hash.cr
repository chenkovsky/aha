module Aha
  # an open address hash table
  class Hat
    struct KV
      @key : Bytes
      @value : ValueT
      getter :key, :value

      def initialize(@key, @value)
      end
    end

    alias ValueT = UInt64*
    @[Extern]
    struct ArrayHash
      include Enumerable(KV)
      alias Slot = UInt8*

      @flag : UInt8
      @c0 : UInt8
      @c1 : UInt8
      @n : UInt64     # number of slots
      @m : UInt64     # number of key/value pairs stored
      @max_m : UInt64 # number of stored keys before we resize
      @slot_sizes : UInt64*
      @slots : Slot*
      MAX_LOAD_FACTOR = 100000.0
      INITIAL_SIZE    = 4096_u64

      protected def self.key_len(s : Slot) : UInt64
        (0x1 & s.value) ? (s.as(UInt16*).value >> 1) : (s.value >> 1)
      end

      def to_io(io : IO, format : IO::ByteFormat)
        @n.to_io io, format
        @m.to_io io, format
        @max_m.to_io io, format

        @flag.to_io io, format
        @c0.to_io io, format
        @c1.to_io io, format
        0_u8.to_io io, format

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

        flag = UInt8.from_io io, format
        c0 = UInt8.from_io io, format
        c1 = UInt8.from_io io, format
        UInt8.from_io io, format

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
        return self.new(n, m, max_m, slot_sizes, slots, flag, c0, c1)
      end

      def initialize(@n, @m, @max_m, @slot_sizes, @slots, @flag, @c0, @c1)
      end

      def initialize(@n = INITIAL_SIZE)
        @flag = 0_u8
        @c0 = 0_u8
        @c1 = 0_u8
        @m = 0
        @max_m = (MAX_LOAD_FACTOR * @n).to_u64
        @slots = Pointer(Slot).malloc(@n, Slot.null)
        @slot_sizes = Ponter(UInt64).malloc(@n, 0_u64)
      end

      def clear
        @n = INITIAL_SIZE
        @slots = Pointer(Slot).malloc(@n, Slot.null)
        @slot_sizes = Pointer(UInt64).malloc(@n, 0_u64)
      end

      def sizeof
        nbytes = sizeof(ArrayHashTable) + @n * (sizeof(UInt64) + sizeof(Slot))
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
      private def ins_key(s : Slot, key : Bytes | Array(UInt8), val : ValueT**) : Slot
        size = key.size
        if size < 128
          s[0] = (size << 1).to_u8
          s += 1
        else
          s.as(UInt16*)[0] = ((size << 1) | 0x1).to_u16
          s += 2
        end

        # key
        s.copy_from key.to_unsafe, size
        s += size

        # val
        val.value = s.as(ValueT*)
        val.value.value = 0
        s += sizeof(ValueT)
        return s
      end

      private def expand
        # Resizing a table is essentially building a brand new one.
        # One little shortcut we can take on the memory allocation front is to
        # figure out how much memory each slot needs in advance.
        new_n = 2 * @n
        slot_sizes = Pointer(UInt64).malloc(new_n, 0_u64)

        each do |key, _|
          slot_sizes[MurMur.hash(key) % new_n] += key.size + sizeof(ValueT) + (len >= 128 ? 2 : 1)
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
        u = Pointer(ValueT).null
        each do |key, v|
          h = MurMur.hash(key) % new_n
          slots_next[h] = ins_key(slots_next[h], key, pointerof(u))
          u.value = v.value
        end
        @slots = slots
        @slot_sizes = slot_sizes
        @n = new_n
        @max_m = (MAX_LOAD_FACTOR * @n).to_u64
      end

      private def get_key(key : Bytes | Array(UInt8), insert_missing : Bool) : Pointer(ValueT)
        expand if insert_missing && @m >= @max_m
        len = key.size
        i = MurMur.hash(key) % @n
        s_start = s = @slots[i]
        slot_size = @slot_sizes[i]
        val = Pointer(ValueT).null
        while (s - s_start) < slot_size
          k = self.key_len s
          s += k < 128 ? 1 : 2
          # skip keys that are longer than ours
          if k != len
            s += k + sizeof(ValueT)
            next
          end
          return (s + len).as(ValueT*) if s.memcmp(key.to_unsafe, len) == 0 # key found
          s += k + sizeof(ValueT)
          next
        end
        if insert_missing
          new_size = @slot_sizes[i]
          new_size += 1 + (len >= 128 ? 1 : 0)
          new_size += len * sizeof(UInt8)
          new_size += sizeof(ValueT)
          @slots[i] = Slot.realloc(new_size)
          @m += 1
          ins_key(@slots[i] + @slot_sizes[i], key, pointerof(val))
          @slot_sizes[i] = new_size
          return val
        end
        return Pointer(ValueT).null
      end

      private def get(key : Bytes | Array(UInt8))
        if key.size > 32767
          raise "HAT-trie/AH-table cannot store keys longer than 32768"
        end
        return get_key key, true
      end

      private def try_get(key : Bytes | Array(UInt8))
        get_key(key, false)
      end

      private def delete(key : Bytes | Array(UInt8))
        i = MurMur.hash(key) % @n
        s_start = s = @slots[i]
        slot_size = @slot_sizes[i]
        while (s - s_start) < slot_size
          k = key_len s
          s += k < 128 ? 1 : 2
          if k != len
            s += k + sizeof(ValueT)
            next
          end
          if s.memcmp(key, len) == 0
            # 找到了当前的key
            t = s + len + sizeof(ValueT)
            s -= k < 128 ? 1 : 2
            s.move_from(t, slot_size - (t - s_start))
            @slot_sizes[i] -= t - s
            @m -= 1
            return 0
          end
          s += k + sizeof(ValueT)
          next
        end
        return -1
      end

      def each(sorted : Bool)
        if sorted
          arr = [] of Bytes
          each do |k, v|
            arr << (KV.new k, v)
          end
          arr.sort_by! { |e| e.key }
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
        @slot_sizes.each_with_index do |size, idx|
          next if size == 0
          slot = @slots[idx]
          s_start = s = @slots[i]
          slot_size = @slot_sizes[i]
          while (s - s_start) < slot_size
            k = key_len s
            s += k < 128 ? 1 : 2
            key = Bytes.new(s, k)
            s += k
            val = s.as(Pointer(ValueT))
            s += sizeof(ValueT)
            yield KV.new key, val
          end
        end
      end
    end
  end
end
