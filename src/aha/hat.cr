require "./array_hash"

module Aha
  # 动态的trie，可以存储任意bytes
  class Hat(N) # N 是 value的byte数
    alias KV = ArrayHash::KV
    include Enumerable(KV)

    class TrieNode(N)
      @has_val : Bool
      @val : StaticArray(UInt8, N)
      @xs : StaticArray(TrieNode(N) | AHNode(N), NODE_CHILDS)
      getter :val, :xs
      setter :val, :has_val

      def has_val?
        @has_val
      end

      def val=(ptr : UInt8*)
        @val = StaticArray(UInt8, N).new { |i| ptr[i] }
      end

      def initialize(@xs : StaticArray(TrieNode(N) | AHNode(N), NODE_CHILDS), @val = StaticArray(UInt8, N).new(0_u8), @has_val = false)
      end

      def initialize(child : TrieNode(N) | AHNode(N), @val = StaticArray(UInt8, N).new(0_u8), @has_val = false)
        @xs = StaticArray(TrieNode(N) | AHNode(N), NODE_CHILDS).new(child.as(TrieNode(N) | AHNode(N)))
      end
    end

    class AHNode(N) < ArrayHash(N)
      @c0 : UInt8
      @c1 : UInt8
      property :c0, :c1

      def pure?
        @c0 == @c1
      end

      def hybrid?
        @c0 != @c1
      end

      def initialize(@c0 = 0_u8, @c1 = Aha::Hat::NODE_MAXCHAR.to_u8, n = ArrayHash::INITIAL_SIZE)
        super n
      end
    end

    MAX_BUCKET_SIZE = 16384_u64
    NODE_MAXCHAR    =      0xff
    NODE_CHILDS     = (Aha::Hat::NODE_MAXCHAR + 1)

    NODE_TYPE_TRIE          = 0x1_u8
    NODE_TYPE_PURE_BUCKET   = 0x2_u8
    NODE_TYPE_HYBRID_BUCKET = 0x4_u8
    NODE_HAS_VAL            = 0x8_u8

    private def self.node_sizeof(node : TrieNode(N) | AHNode(N)) : UInt64
      if node.is_a? TrieNode(N)
        nbytes = sizeof(TrieNode(N))
        (0...NODE_CHILDS).each do |i|
          if node.xs[i] != node.xs[i - 1]
            nbytes += node_sizeof(node.xs[i])
          end
        end
        return nbytes
      else
        node.sizeof
      end
    end

    @root : TrieNode(N)
    @m : UInt64

    def size
      @m
    end

    def sizeof
      sizeof(self) + node_sizeof(@root)
    end

    # Create a new trie node with all pointers pointing to the given child (which
    # can be NULL).
    # TrieNode.new(NODE_TYPE_TRIE, 0, StaticArray.new(child))

    # 在trie上消耗给定的字符串， 返回得到的节点，
    # 并且输出消耗后的结尾和剩余的字符串长度
    private def consume(p : TrieNode(N)*, k : UInt8**, l : UInt64*, brk : UInt32)
      node = p.value.xs[k[0][0]]
      while (node.is_a? TrieNode(N)) && (l[0] > brk)
        k.value += 1
        l.value -= 1
        p.value = node
        node = node.as(TrieNode(N)).xs[k[0][0]]
      end
      return node
    end

    # find node in trie
    # 写回消耗后的字符串头和字符串的长度， 返回得到的节点
    private def find(key : UInt8**, len : UInt64*) # : TrieNode(N) | AHNode(N) | Nil
      parent = @root
      # assert parent[0] & NODE_TYPE_TRIE
      return parent if len.value == 0
      node = consume(pointerof(parent), key, len, 1_u32)

      # if the trie node consumes value, use it
      if node.is_a? TrieNode(N)
        return nil unless node.has_val?
        return node
      end

      # pure bucket holds only key suffixes, skip current char
      if node.pure?
        key.value += 1
        len.value -= 1
      end

      # do not scan bucket, it's not needed for this operation
      return node
    end

    def initialize
      @m = 0_u64
      @root = TrieNode.new(AHNode(N).new)
    end

    def clear
      @m = 0_u64
      @root = TrieNode.new(AHNode(N).new)
    end

    # Perform one split operation on the given node with the given parent.
    private def split(parent : TrieNode(N), node : AHNode(N))
      # only buckets may be split
      # parent must be trienode
      if node.pure?
        # node.b.value.c0 == node.b.value.c1 时才是pure bucket
        parent.xs[node.c0] = t_node = TrieNode.new(node)
        val = node.try_get(Slice(UInt8).empty) # 值的指针
        if val != Pointer(UInt8).null
          t_node.val = val
          node.delete Slice(UInt8).empty
        end
        node.c0 = 0x00_u8
        node.c1 = NODE_MAXCHAR.to_u8
      end

      # This is a hybrid bucket. Perform a proper split.
      # count the number of occourances of every leading character

      cs = StaticArray(UInt32, NODE_CHILDS).new(0_u32)
      node.each { |kv| cs[kv.key[0]] += 1 }

      # choose a split point
      j = node.c0 # c0 是最小的子节点的char, c1 是最大
      all_m = node.size
      left_m = cs[j]
      right_m = all_m - left_m

      while j + 1 < node.c1
        d = ((left_m + cs[j + 1]).to_i32 - (right_m - cs[j + 1]).to_i32).abs
        if d <= (left_m - right_m).abs && left_m + cs[j + 1] < all_m
          # 表示分得更加平衡了
          j += 1
          left_m += cs[j]
          right_m -= cs[j]
        else
          # 不能更加平衡了，就是这里了
          break
        end
      end

      # now split into two node cooresponding to ranges [0, j] and
      # [j + 1, NODE_MAXCHAR], respectively. */

      # create new left and right nodes

      # TODO: Add a special case if either node is a hybrid bucket containing all
      # the keys. In such a case, do not build a new table, just use the old one.

      num_slots = ArrayHash::INITIAL_SIZE
      while left_m > ArrayHash::MAX_LOAD_FACTOR * num_slots
        num_slots *= 2
      end
      # 找到left array hash 需要的初始化大小

      left = AHNode(N).new(node.c0, j.to_u8, num_slots)

      num_slots = ArrayHash::INITIAL_SIZE
      while right_m > ArrayHash::MAX_LOAD_FACTOR * num_slots
        num_slots *= 2
      end
      # 找到 right array hash 需要的初始化大小
      right = AHNode(N).new(j + 1, node.c1, num_slots)

      (node.c0..j).each { |c| parent.xs[c] = left }
      ((j + 1)..node.c1).each { |c| parent.xs[c] = right }
      node.each do |kv|
        cur_node = kv.key[0] <= j ? left : right
        if cur_node.pure?
          v = cur_node.get(kv.key + 1)
        else
          v = cur_node.get(kv.key)
        end
        kv.value.copy_to(v, kv.value.size)
      end
    end

    def get(key : Bytes | Array(UInt8)) : UInt8*
      parent = @root
      # assert parent[0] & NODE_TYPE_TRIE
      return parent.val.to_unsafe if key.size == 0
      key_ptr = key.to_unsafe
      len = key.size.to_u64
      node = consume(pointerof(parent), pointerof(key_ptr), pointerof(len), 0_u32)

      # if the key has been consumed on a trie node, use its value
      if len == 0
        if node.is_a? TrieNode(N)
          node.has_val = true
          return node.val.to_unsafe
        end
        if node.hybrid?
          parent.has_val = true
          return parent.val.to_unsafe
        end
      end

      # preemptively split the bucket if it is full
      while node.as(AHNode(N)).size >= MAX_BUCKET_SIZE
        split parent, node.as(AHNode(N))
        node = consume pointerof(parent), pointerof(key_ptr), pointerof(len), 0_u32
        if len == 0
          if node.is_a? TrieNode(N)
            node.has_val = true
            return node.val.to_unsafe
          end
          if node.hybrid?
            parent.has_val = true
            return parent.val.to_unsafe
          end
        end
      end
      # assert node[0] & NODE_TYPE_PURE_BUCKET || node[0] & NODE_TYPE_HYBRID_BUCKET
      # assert key.size > 0
      m_old = node.as(AHNode(N)).size

      if node.as(AHNode(N)).pure?
        v = node.as(AHNode(N)).get(Bytes.new(key_ptr + 1, len - 1))
      else
        v = node.as(AHNode(N)).get(Bytes.new(key_ptr, len))
      end
      @m += node.as(AHNode(N)).size - m_old
      return v
    end

    def try_get(key : Bytes) : UInt8*
      key_ptr = key.to_unsafe
      key_size = key.size.to_u64
      node = find pointerof(key_ptr), pointerof(key_size)
      return Pointer(UInt8).null if node.nil?
      return node.val.to_unsafe if node.is_a? TrieNode(N)
      return node.try_get(Bytes.new(key_ptr, key_size))
    end

    def delete(key : Bytes) : Bool
      key_ptr = key.to_unsafe
      key_size = key.size.to_u64
      parent = @root
      # assert parent[0] & NODE_TYPE_TRIE
      node = find pointerof(key_ptr), pointerof(key_size)
      return false if node.nil?
      return node.val = nil if node.is_a? TrieNode(N)
      m_old = node.size
      ret = node.delete Bytes.new(key_ptr, key_size)
      @m -= (m_old - @m.size)
      return ret
    end

    def []=(k : String, v)
      self[Bytes.new(k.to_unsafe, k.bytesize)] = v
    end

    def []=(k : Array(UInt8) | Bytes, v)
      get(k).copy_from v.to_unsafe, N
    end

    def []?(k : String)
      self[Bytes.new(k.to_unsafe, k.bytesize)]?
    end

    def [](k : String)
      self[Bytes.new(k.to_unsafe, k.bytesize)]
    end

    def []?(k : Bytes)
      ptr = try_get k
      return nil if ptr == Pointer(UInt8).null
      return Bytes.new(ptr, N)
    end

    def [](k : Bytes)
      ret = self[k]?
      raise IndexError.new if ret.nil?
      return ret
    end

    class Stack(N)
      @c : UInt8
      @node : TrieNode(N) | AHNode(N)
      @level : UInt64
      @next : Stack(N)?
      property :c, :node, :level, :next

      def initialize(@c, @node, @level, @next = nil)
      end
    end

    private def merge_chars(arr1, arr2)
      Bytes.new(arr1.size + arr2.size) do |i|
        i >= arr1.size ? arr2[i - arr1.size] : arr1[i]
      end
    end

    private def push_char(arr : Array(UInt8), level : UInt64, c : UInt8)
      (arr.size...level).each do |i|
        arr << 0_u8
      end
      arr[level - 1] = c if level > 0
    end

    def each(sorted : Bool = false)
      stack = Stack(N).new(0_u8, @root, 0_u64)
      key = [] of UInt8
      level = 0
      while !stack.nil?
        node, c, level = stack.node, stack.c, stack.level
        if node.is_a? TrieNode(N)
          push_char key, level, c
          if node.has_val?
            yield KV.new(Bytes.new(key.size) { |i| key[i] }, Bytes.new(N) { |i| node.val[i] })
          end
          stack = stack.next
          (0..NODE_MAXCHAR).reverse_each do |j|
            # skip repeated pointers to hybrid bucket
            next if j < NODE_MAXCHAR && node.xs[j] == node.xs[j + 1]
            stack = Stack(N).new(j.to_u8, node.xs[j], level + 1, stack)
          end
        else
          if node.pure?
            key << c
          else # hybrid bucket
            level -= 1
          end
          node.each(sorted) do |kv|
            yield KV.new(merge_chars(key, kv.key), Bytes.new(N) { |i| kv.value[i] })
          end
          stack = stack.next # 没有子节点了
        end
      end
    end
  end
end
