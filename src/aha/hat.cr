module Aha
  class Hat(T) # N is trie node type
    include Enumerable(KV)

    def self.compile(kv : Hash(Bytes, UInt64) | Hash(String, UInt64))
      trie = Hat.new
      kv.each do |k, v|
        trie[k] = v
      end
      trie
    end

    struct KV
      @key : Bytes
      @value : ValueT
      getter :key, :value

      def initialize(@key, @value)
      end
    end

    @[Extern]
    struct TrieNode
      @flag : UInt8
      @val : ValueT
      @xs : StaticArray(NodePtr, NODE_CHILDS)

      def initialize(@flag, @xs, @val = ValueT.null)
      end
    end

    MAX_BUCKET_SIZE = 16384_u64
    NODE_MAXCHAR    =      0xff
    NODE_CHILDS     = (NODE_MAXCHAR + 1)

    NODE_TYPE_TRIE          = 0x1_u8
    NODE_TYPE_PURE_BUCKET   = 0x2_u8
    NODE_TYPE_HYBRID_BUCKET = 0x4_u8
    NODE_HAS_VAL            = 0x8_u8

    @[Extern(union: true)]
    struct NodePtr
      @b = uninitialized Pointer(ArrayHash)
      @t = uninitialized Pointer(TrieNode)
      @flag = uninitialized Pointer(UInt8)
      property :b, :t, :flag
    end

    private def self.node_sizeof(node : NodePtr) : UInt64
      if node.flag[0] & NODE_TYPE_TRIE
        nbytes = sizeof(TrieNode)
        (0...NODE_CHILDS).each do |i|
          if node.t.value.xs[i] != node.t.value.xs[i - 1]
            nbytes += node_sizeof(node.t.xs[i])
          end
        end
        return nbytes
      else
        node.b.value.sizeof
      end
    end

    @root : NodePtr
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
    private def consume(p : NodePtr*, k : UInt8**, l : UInt64*, brk : UInt32) : UInt8*
      node = p.value.t.xs[k[0][0]]
      while (node.flag[0] & NODE_TYPE_TRIE) && (l[0] > brk)
        k.value += 1
        l.value -= 1
        p.value = node
        node = node.t.xs[k[0][0]]
      end
      # assert p[0] * NODE_TYPE_TRIE
      return node
    end

    # use node value and return pointer to it
    private def useval(n : UInt8*) : ValueT*
      if !n.t.value.flag & NODE_HAS_VAL
        n.t.value.flag |= NODE_HAS_VAL
        @m += 1
      end
      return pointerof(n.t.value.val)
    end

    private def clrval(n : NodePtr)
      if n.t.value.flag & NODE_HAS_VAL
        n.t.value.flag &= ~NODE_HAS_VAL
        n.t.value.val = 0
        @m -= 1
        return 0
      end
      return -1
    end

    # find node in trie
    private def find(key : UInt8**, len : UInt64*)
      parent = @root
      # assert parent[0] & NODE_TYPE_TRIE
      return parent if len.value == 0
      node = consume(pointerof(parent), key, len, 1)
      if node.flag[0] & NODE_TYPE_TRIE
        if !node.t.value.flag & NODE_HAS_VAL
          node.flag = Pointer(UInt8).null
        end
        return node
      end
      if node.flag[0] & NODE_TYPE_PURE_BUCKET
        key.value += 1
        len.value -= 1
      end
      return node
    end

    def initialize
      @m = 0
      node = ArrayHashTable.new
      node.flag = NODE_TYPE_HYBRID_BUCKET
      node.c0 = 0x00
      node.c1 = NODE_MAXCHAR
      @root = NodePtr.new
      @root.t = TrieNode.new(NODE_TYPE_TRIE, 0, StaticArray(NodePtr, NODE_CHILDS).new(node))
    end

    def clear
      @m = 0
      node = ArrayHashTable.new
      node.flag = NODE_TYPE_HYBRID_BUCKET
      node.c0 = 0x00
      node.c1 = NODE_MAXCHAR
      @root = NodePtr.new
      @root.t = TrieNode.new(NODE_TYPE_TRIE, 0, StaticArray(NodePtr, NODE_CHILDS).new(node))
    end

    # Perform one split operation on the given node with the given parent.
    private def split(parent : NodePtr, node : NodePtr)
      # only buckets may be split
      # assert node[0] & NODE_TYPE_PURE_BUCKET || node[0] & NODE_TYPE_HYBRID_BUCKET
      # assert parent[0] & NODE_TYPE_TRIE
      if node.flag[0] & NODE_TYPE_PURE_BUCKET
        # node.b.value.c0 == node.b.value.c1 时才是pure bucket
        parent.t.value.xs[node.b.value.c0] = TrieNode.new(NODE_TYPE_TRIE, 0, StaticArray(NodePtr, NODE_CHILDS).new(node))
        val = node.b.value.try_get(Slice(UInt8).empty)
        if val
          ptr = parent.t.value.xs[node.b.value.c0].t
          ptr.value.val = val.value
          ptr.value.flag |= NODE_HAS_VAL
          val.value = 0
          node.b.value.delete Slice(UInt8).empty
        end
        node.b.value.c0 = 0x00
        node.b.value.c1 = NODE_MAXCHAR
        node.b.value.flag = NODE_TYPE_HYBRID_BUCKET
      end

      # This is a hybrid bucket. Perform a proper split.
      # count the number of occourances of every leading character

      cs = StaticArray(UInt32, NODE_CHILDS).new(0_u32)
      node.b.value.each { |key, val| cs[key[0]] += 1 }

      # choose a split point
      j = node.b.value.c0 # c0 是最小的子节点的char, c1 是最大
      all_m = node.b.value.size
      left_m = cs[j]
      right_m = all_m - left_m

      while j + 1 < node.b.value.c1
        d = Math.abs((left_m + cs[j + 1]).to_i32 - (right_m - cs[j + 1]).to_i32)
        if d <= Math.abs(left_m - right_m) && left_m + cs[j + 1] < all_m
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
      while left_m > MAX_LOAD_FACTOR * num_slots
        num_slots *= 2
      end
      # 找到left array hash 需要的初始化大小

      left_b = ArrayHash.new(num_slots)
      left_b.c0 = node.b.value.c0
      left_b.c1 = j
      left_b.flag = (left_b.c0 == left_b.c1) ? NODE_TYPE_PURE_BUCKET : NODE_TYPE_HYBRID_BUCKET

      num_slots = ArrayHashTable::INITIAL_SIZE
      while right_m > MAX_LOAD_FACTOR * num_slots
        num_slots *= 2
      end
      # 找到 right array hash 需要的初始化大小
      right_b = ArrayHashTable.new(num_slots)
      right_b.c0 = j + 1
      right_b.c1 = node.b.value.c1
      right_b.flag = (right_b.c0 == right_b.c1) ? NODE_TYPE_PURE_BUCKET : NODE_TYPE_HYBRID_BUCKET

      # update the parent's pointer

      left = NodePtr.new
      left.b = left_b
      right = NodePtr.new
      right.b = right_b

      (node.b.value.c0..j).each { |c| parent.t.value.xs[c] = left }
      ((j + 1)..node.b.value.c1).each { |c| parent.t.value.xs[c] = right }
      node.b.value.each do |key, val|
        if key[0] <= j
          # left
          if left.flag[0] & NODE_TYPE_PURE_BUCKET
            v = left_b.get(key + 1)
          else
            v = left_b.get(key)
          end
          v.value = val.value
        else
          # right
          if right.flag[0] & NODE_TYPE_PURE_BUCKET
            v = right_b.get(key + 1)
          else
            v = right_b.get(key)
          end
          v.value = val.value
        end
      end
    end

    def get(key : Bytes | Array(UInt8)) : ValueT
      parent = @root
      # assert parent[0] & NODE_TYPE_TRIE
      return parent.t.value.val if key.size == 0
      node = consume(pointerof(parent), key, 0)
      # assert parent[0] & NODE_TYPE_TRIE

      # if the key has been consumed on a trie node, use its value
      if key.size == 0
        if node.flag[0] & NODE_TYPE_TRIE
          return useval(node)
        elsif node.flag[0] & NODE_TYPE_HYBRID_BUCKET
          return useval(parent)
        end
      end

      # preemptively split the bucket if it is full
      while node.b.value.size >= MAX_BUCKET_SIZE
        split parent, node
        node = consume parent, key, 0
        if key.size == 0
          if node.flag[0] & NODE_TYPE_TRIE
            return useval node
          elsif node.flag[0] & NODE_TYPE_HYBRID_BUCKET
            return useval parent
          end
        end
      end
      # assert node[0] & NODE_TYPE_PURE_BUCKET || node[0] & NODE_TYPE_HYBRID_BUCKET
      # assert key.size > 0
      m_old = node_b.value.m
      if node.flag[0] & NODE_TYPE_PURE_BUCKET
        val = get(node_b, key + 1)
      else
        val = get(node_b, key)
      end
      @m += node_b.value.m - m_old
      return val
    end

    def try_get(key : Slice(UInt8))
      node = find key
      if node == Pointer.null
        return node
      end
      if node.flag[0] & NODE_TYPE_TRIE
        return node.t.val
      end
      return node.b.try_get(key)
    end

    def delete(key : Slice(UInt8))
      parent = @root
      # assert parent[0] & NODE_TYPE_TRIE
      node = find key
      if node == Pointer.null
        return -1
      end
      if node.flag[0] == NODE_TYPE_TRIE
        return clrval node
      end
    end

    def []=(k : String, v)
      self[Bytes.new(k.to_unsafe, k.bytesize)] = v
    end

    def []=(k : Array(UInt8) | Bytes, v)
      get(k).value = v
    end

    def []?(k)
      ptr = try_get k
      return nil if ptr == Pointer(ValueT).null
      return ptr.value
    end

    struct Stack
      @c : UInt8
      @node : NodePtr
      @level : UInt64
      @next : Stack*
      property :c, :node, :level, :next
      def initialize(@c, @node, @level, @next = Pointer(Stack).null)
      end
    end

    private def merge_chars(arr1, arr2)
      Bytes.new(arr1.size+arr2.size) do |i|
        i >= arr1.size ? arr2[i - arr1.size] : arr1[i]
      end
    end

    private def push_char(arr : Array(UInt8), level : UInt64, c : UInt8)
      (arr.size...level).each do |i|
        arr << 0_u8
      end
      arr[level - 1] = c
    end

    def each(sorted : Bool = false)
      stack = Stack.new(@root, 0_u8, 0})
      key = [] of UInt8
      level = 0
      while !stack.nil?
        node, c, level = stack.node, stack.c, stack.level
        if node.flag[0] & NODE_TYPE_TRIE
          push_char key, level, c
          if node.t.value.flag & NODE_HAS_VAL
            yield KV.new(key, node.t.value.val)
          end
          stack = stack.next
          (0..NODE_MAXCHAR).reverse_each do |j|
            # skip repeated pointers to hybrid bucket
            next if j < NODE_MAXCHAR && node.t.value.xs[j].t == node.t.value.xs[j+1].t
            stack = Stack.new(j, node.t.value.xs[j], level + 1, stack)
          end
        else
          if node.flag[0] & NODE_TYPE_PURE_BUCKET
            key << c
          else # hybrid bucket
            level -= 1
          end
          node.b.value.each(sorted) do |kv|
            yield KV.new(merge_chars(key, kv.key), kv.v)
          end
          stack = stack.next # 没有子节点了
        end
      end
    end
  end
end
