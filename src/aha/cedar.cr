module Aha
  alias Cedar = CedarX(Int32)
  alias CedarBig = CedarX(Int64)

  class CedarX(T)
    def self.value_limit
      T::MAX
    end

    include Enumerable({String, T})

    struct NodeDesc(T)
      @id : T
      @label : UInt8
      getter :id, :label

      def initialize(@id, @label)
      end
    end

    struct Node(T)
      @value : T
      @check : T
      @sibling : UInt8
      @child : UInt8
      @flags : UInt16 # 低九位表示孩子数目

      protected property :value, :check, :sibling, :child, :flags

      def to_io(io : IO, format : IO::ByteFormat)
        @value.to_io io, format
        @check.to_io io, format
        @sibling.to_io io, format
        @child.to_io io, format
        @flags.to_io io, format
      end

      def self.from_io(io : IO, format : IO::ByteFormat) : self
        n = Node(T).new(0, 0)
        n.value = T.from_io io, format
        n.check = T.from_io io, format
        n.sibling = UInt8.from_io io, format
        n.child = UInt8.from_io io, format
        n.flags = UInt16.from_io io, format
        n
      end

      def initialize(@value, @check)
        @flags = 0_u16
        @child = 0_u8
        @sibling = 0_u8
      end

      CHILD_NUM_MASK = (1 << 9) - 1
      END_MASK       = 1 << 9

      def child_num
        @flags & CHILD_NUM_MASK
      end

      def child_num=(val)
        @flags = (@flags & ~CHILD_NUM_MASK) | val
      end

      def end? : Bool
        (@flags & END_MASK) != 0
      end

      def end!
        @flags |= END_MASK
      end

      def base : T
        -(@value + 1)
      end

      def is_child?(par) : Bool
        @check == par
      end

      def child_ptr
        pointerof(@child)
      end

      def sibling_ptr
        pointerof(@sibling)
      end
    end

    struct Block(T)
      @prev : T
      @next : T
      @num : Int32
      @reject : Int32
      @trial : Int32
      @ehead : T

      property :prev, :next, :num, :reject, :trial, :ehead

      def to_io(io : IO, format : IO::ByteFormat)
        @prev.to_io io, format
        @next.to_io io, format
        @num.to_io io, format
        @reject.to_io io, format
        @trial.to_io io, format
        @ehead.to_io io, format
      end

      def self.from_io(io : IO, format : IO::ByteFormat) : self
        prev = T.from_io io, format
        next_ = T.from_io io, format
        num = Int32.from_io io, format
        reject = Int32.from_io io, format
        trial = Int32.from_io io, format
        ehead = T.from_io io, format
        Block(T).new(prev, next_, trial, ehead, num, reject)
      end

      def initialize(@prev, @next, @trial, @ehead, @num = 256, @reject = 257)
      end
    end

    @key_num : T
    @key_capacity : T
    @array : Pointer(Node(T))
    @blocks : Pointer(Block(T))
    @reject : StaticArray(Int32, 257)
    @bheadF : T
    @bheadC : T
    @bheadO : T
    @array_size : T
    @capacity : T
    @ordered : Bool
    @max_trial : Int32
    @leafs : Pointer(T) # 每个key 的 id对应的leaf的node的id
    @leaf_size : T

    protected setter :array, :blocks, :reject, :bheadF, :bheadC, :bheadO, :array_size, :ordered, :max_trial, :leafs, :key_num, :capacity, :key_capacity
    protected getter :array, :array_size, :capacity

    def key_num
      @key_num
    end

    def size
      @key_num
    end

    def root
      0
    end

    def node(nid : T) : Pointer(Node(T))
      Aha.pointer(@array, nid)
    end

    def to_io(io : IO, format : IO::ByteFormat)
      Aha.ptr_to_io @array, @array_size, Node(T), io, format
      Aha.ptr_to_io @blocks, (@array_size >> 8), Block(T), io, format
      @reject.each { |r| r.to_io io, format }
      Aha.ptr_to_io @leafs, (@key_num), T, io, format
      @bheadF.to_io io, format
      @bheadC.to_io io, format
      @bheadO.to_io io, format
      (@ordered ? 1 : 0).to_io io, format
      @max_trial.to_io io, format
    end

    def self.from_io(io : IO, format : IO::ByteFormat) : self
      c = Cedar.new
      c.array, array_size, capacity = Aha.ptr_from_io Node(T), io, format, Math.pw2ceil
      c.array_size = T.new(array_size)
      c.capacity = T.new(capacity)
      c.blocks, _, _ = Aha.ptr_from_io Block(T), io, format, Math.pw2ceil
      c.reject = StaticArray(Int32, 257).new { |i| Int32.from_io io, format }
      c.leafs, key_num, key_capacity = Aha.ptr_from_io T, io, format, Math.pw2ceil
      c.key_num = T.new(key_num)
      c.key_capacity = T.new(key_capacity)
      c.bheadF = T.from_io io, format
      c.bheadC = T.from_io io, format
      c.bheadO = T.from_io io, format
      c.ordered = Int32.from_io(io, format) != 0
      c.max_trial = Int32.from_io io, format
      return c
    end

    def initialize(@ordered = false)
      raise "CedarX's type parameter should be Int32 or Int64" if T != Int32 && T != Int64

      @capacity = T.new(256)
      @key_num = T.new(0)
      @leaf_size = T.new(0)
      @key_capacity = @capacity
      @leafs = Pointer(T).malloc(@key_capacity)
      @array = Pointer(Node(T)).malloc(@capacity)
      @array_size = @capacity
      @blocks = Pointer(Block(T)).malloc(@capacity >> 8)
      @max_trial = 1
      @array[0] = Node(T).new(T.new(-1), T.new(-1))
      # array 第一个节点空置
      (1...256).each { |i| @array[i] = Node(T).new(T.new(-(i - 1)), T.new(-(i + 1))) }
      Aha.at(@array, 1).value = T.new(-255)
      Aha.at(@array, 255).check = T.new(-1)
      @blocks[0] = Block(T).new(T.new(0), T.new(0), 0, T.new(1))
      @reject = StaticArray(Int32, 257).new { |i| i + 1 }
      @bheadF = T.new(0)
      @bheadC = T.new(0)
      @bheadO = T.new(0)
    end

    # 从 key 的 start 位开始, 从 from 节点开始遍历，如果没有节点就创建节点, 返回最终的叶子节点
    private def get(key : Bytes | Array(UInt8), from : T, start : T) : T
      (start...key.size).each do |pos|
        value = Aha.at(@array, from).value
        if value >= 0 && value != self.class.value_limit
          # 原本这个节点是叶子节点，值就存储在base里面，现在不是叶子节点了。
          # 所以需要新建一个叶子节点。
          # 其实完全可以一开始就新建\0 节点，现在这么做是为了节省空间
          to = follow(from, 0_u8)
          Aha.at(@array, to).value = value
          @leafs[value] = to
        end
        from = follow(from, key[pos])
      end
      # value < 0 时 base >= 0, 说明不是叶子节点
      # value >= 0 时 base < 0, 说明是叶子节点
      Aha.at(@array, from).value < 0 ? follow(from, 0_u8) : from
    end

    # 从 from 开始，如果没有label的子节点，那么创建，返回子节点的id
    private def follow(from : T, label : UInt8) : T
      base = Aha.at(@array, from).base
      to = base ^ label
      if base < 0 || Aha.at(@array, to).check < 0
        # 当前节点没有子节点 || 需要存放的地方没有被占用。
        # has_child 当前节点是否还有其他节点
        has_child = base >= 0 && (Aha.at(@array, base ^ Aha.at(@array, from).child).check == from)
        to = pop_enode base, label, from
        # 添加当前的子节点
        push_sibling from, to ^ label, label, has_child
      elsif Aha.at(@array, to).check != from
        # 需要存放的地方已经被占用了
        to = resolve from, base, label
      end
      to
    end

    # 将 block bi 从双向链表中拿出
    # params:
    #   bi 当前 block 的 id
    #   head_in 当前 block 链表的头部指针
    #   last 当前block 是否是列表中最后一个block
    private def pop_block(bi : T, head_in : Pointer(T), last : Bool) : Void
      if last
        head_in.value = T.new(0)
      else
        b = Aha.pointer @blocks, bi
        Aha.at(@blocks, b.value.prev).next = b.value.next
        Aha.at(@blocks, b.value.next).prev = b.value.prev
        if bi == head_in.value
          # 如果双向列表的头 是 bi 那么应该将头设为bi的next
          head_in.value = b.value.next
        end
      end
    end

    # 将 bi 放入双向列表
    # params:
    #   bi 当前block的id
    #   head_out 目标block链表的头部
    #   empty headout链表是否为空
    private def push_block(bi : T, head_out : Pointer(T), empty : Bool) : Void
      b = Aha.pointer @blocks, bi
      if empty
        head_out.value, b.value.prev, b.value.next = bi, bi, bi
      else
        tail_out = Aha.pointer @blocks, head_out.value
        b.value.prev = tail_out.value.prev
        b.value.next = head_out.value
        Aha.at(@blocks, tail_out.value.prev).next = bi
        head_out.value, tail_out.value.prev = bi, bi
      end
    end

    # 增加一个可用的block, 返回 block 的 id
    private def add_block : T
      if @array_size == @capacity
        @capacity *= 2
        @blocks = @blocks.realloc((@capacity >> 8))
        @array = @array.realloc(@capacity)
      end

      @blocks[@array_size >> 8] = Block(T).new(T.new(0), T.new(0), 0, @array_size)
      (0...256).each do |i|
        @array[@array_size + i] = Node(T).new(T.new(-(((i + 255) & 255) + @array_size)), T.new(-(((i + 1) & 255) + @array_size)))
      end
      push_block @array_size >> 8, pointerof(@bheadO), @bheadO == 0
      @array_size += 256
      (@array_size >> 8) - 1
    end

    # 将 block 放入另一个队列
    # params:
    #   bi : 当前block id
    #   head_in : 原来block的头部指针
    #   head
    private def transfer_block(bi : T, head_in : Pointer(T), head_out : Pointer(T))
      pop_block bi, head_in, bi == Aha.at(@blocks, bi).next # 当一个双向列表的next是自己时，说明列表中只有一个元素了
      push_block bi, head_out, head_out.value == 0 && Aha.at(@blocks, bi).num != 0
    end

    # 找到一个空的节点，返回节点 id
    # from 为 父节点， base 为该父节点的 base
    # 如果 from 未曾有过子节点，那么给 from 设置一下 base
    # 设置好了子节点的check
    private def pop_enode(base : T, label : UInt8, from : T) : T
      e = base < 0 ? find_place : (base ^ label) # 如果还没有任何子节点，给其找个位置
      bi = e >> 8
      n = Aha.pointer @array, e
      b = Aha.pointer @blocks, bi
      b.value.num = b.value.num - 1 # 该block中剩余的slot数目减少
      if b.value.num == 0
        # O 队列 > 1 个 slot
        # C 队列 = 1 个 slot
        # F 队列 没有 slot
        # 如果该 block 中已经没有空余的slot，那么从 C 队列 放入 F 队列
        transfer_block bi, pointerof(@bheadC), pointerof(@bheadF) unless bi == 0
      else
        # 所有的 slot 其实在未分配的时候也是用 双向列表在管理
        # 此时从双向列表中移除这个slot
        # check 和 value 分别是 prev 和 next
        Aha.at(@array, -n.value.value).check = n.value.check
        Aha.at(@array, -n.value.check).value = n.value.value
        if e == b.value.ehead
          b.value.ehead = -n.value.check
        end
        if bi != 0 && b.value.num == 1 && b.value.trial != @max_trial
          # 如果只有一个slot了，那么从 O 队列放入 C 队列
          transfer_block bi, pointerof(@bheadO), pointerof(@bheadC)
        end
      end
      n.value.value = self.class.value_limit
      n.value.check = from
      Aha.at(@array, from).value = -(e ^ label) - 1 if base < 0
      e
    end

    private def push_enode(e : T)
      e_ptr = Aha.pointer @array, e
      bi = e >> 8
      b = Aha.pointer @blocks, bi
      b.value.num = b.value.num + 1
      if b.value.num == 1
        # 如果 block 中原来没有slot。现在有了
        # 从 F 链 放入 C 链
        b.value.ehead = e
        e_ptr.value.value = -e
        e_ptr.value.check = -e
        transfer_block bi, pointerof(@bheadF), pointerof(@bheadC) unless bi == 0
      else
        # 原本就有， 首先放入队列
        prev = b.value.ehead
        prev_ptr = Aha.pointer @array, prev
        next_ = -prev_ptr.value.check
        e_ptr.value.value = -prev
        e_ptr.value.check = -next_
        prev_ptr.value.check = -e
        Aha.at(@array, next_).value = -e
        if b.value.num == 2 || b.value.trial == @max_trial
          # 如果刚好达到两个，那么就需要从, C 队列，放入 O 队列
          transfer_block bi, pointerof(@bheadC), pointerof(@bheadO) unless bi == 0
        end
        b.value.trial = 0
      end
      # reject 是说多少子节点的话，就应该直接不查这个大小的block了。
      if b.value.reject < @reject[b.value.num]
        b.value.reject = @reject[b.value.num]
      end

      # 清空 node 信息
      e_ptr.value.child = 0_u8
      e_ptr.value.sibling = 0_u8
      e_ptr.value.flags = 0_u16
    end

    # 将 label 加入子节点的链表， 在已经分配好空间的情况下，调用此函数
    # params:
    #   from 父节点id
    #   label 当前节点 label
    private def push_sibling(from : T, base : T, label : UInt8, has_child : Bool)
      from_ptr = Aha.pointer @array, from
      child_ptr = from_ptr.value.child_ptr
      keep_order = @ordered ? (label > child_ptr.value) : (child_ptr.value == 0)
      if has_child && keep_order
        child_ptr = Aha.at(@array, (base ^ child_ptr.value)).sibling_ptr
        while @ordered && child_ptr.value != 0 && child_ptr.value < label
          c = Aha.at(@array, base ^ child_ptr.value).sibling_ptr
        end
      end
      # 加入 sibling 的链表
      Aha.at(@array, (base ^ label)).sibling = child_ptr.value
      child_ptr.value = label
      from_ptr.value.child_num = from_ptr.value.child_num + 1
    end

    # 将 label 节点从 sibling 链表移出
    private def pop_sibling(from : T, label : UInt8)
      from_ptr = Aha.pointer @array, from
      base = from_ptr.value.base
      child_ptr = from_ptr.value.child_ptr
      while child_ptr.value != label
        child_ptr = Aha.at(@array, (base ^ child_ptr.value)).sibling_ptr
      end
      child_ptr.value = Aha.at(@array, (base ^ child_ptr.value)).sibling
      from_ptr.value.child_num = from_ptr.value.child_num - 1
    end

    # 是否保留 pnode
    private def consult(nref : Pointer(Node(T)), pref : Pointer(Node(T))) : Bool
      nref.value.child_num < pref.value.child_num
    end

    def has_label?(id : T, label : UInt8) : Bool
      child(id, label) >= 0
    end

    # 返回 子节点 的 id
    def child(id : T, label : UInt8) : T # < 0 说明不存在
      parent_ptr = Aha.pointer @array, id
      base = parent_ptr.value.base
      cid = base ^ label
      return -1 if cid < 0 || cid >= @array_size || !Aha.at(@array, cid).is_child?(id)
      return cid
    end

    # yield 所有子节点的 id, label
    def children(id : T, &block)
      parent_ptr = Aha.pointer @array, id
      base = parent_ptr.value.base
      s = parent_ptr.value.child
      if s == 0 && base > 0
        s = Aha.at(@array, base).sibling
      end
      while s != 0
        to = base ^ s
        break if to < 0
        yield NodeDesc(T).new(to, s)
        s = Aha.at(@array, to).sibling
      end
    end

    protected def first_child(id : T) : NodeDesc(T)?
      return nil if id < 0
      parent_ptr = Aha.pointer @array, id
      base = parent_ptr.value.base
      s = parent_ptr.value.child
      if s == 0 && base > 0
        s = Aha.at(@array, base).sibling
      end
      if s != 0
        to = base ^ s
        return nil if to < 0
        return NodeDesc(T).new(to, s)
      end
      return nil
    end

    protected def sibling(to : T) : NodeDesc(T)?
      return nil if to < 0
      base = Aha.at(@array, Aha.at(@array, to).check).base
      s = Aha.at(@array, to).sibling
      return nil if s == 0
      to = base ^ s
      return NodeDesc(T).new(to, s)
    end

    def children(id : T) : Array(NodeDesc(T))
      req = [] of NodeDesc(T)
      children(id).each do |c|
        req << c
      end
      return req
    end

    private def set_child(base : T, c : UInt8, label : UInt8, append_label : Bool, children : Pointer(UInt8)) : Int32
      idx = 0
      if c == 0
        children[idx] = c
        idx += 1
        c = Aha.at(@array, base ^ c).sibling
      end

      if @ordered
        while c != 0 && c <= label
          children[idx] = c
          idx += 1
          c = Aha.at(@array, base ^ c).sibling
        end
      end
      if append_label
        children[idx] = label
        idx += 1
      end
      while c != 0
        children[idx] = c
        idx += 1
        c = Aha.at(@array, base ^ c).sibling
      end
      return idx
    end

    # 找一个位置
    def find_place : T
      return @blocks[@bheadC].ehead if @bheadC != 0
      return @blocks[@bheadO].ehead if @bheadO != 0
      return add_block << 8
    end

    # 给所有的 child 找位置
    def find_places(children_ : Pointer(UInt8), children_size) : T
      bi = @bheadO
      if bi != 0
        bz = Aha.at(@blocks, @bheadO).prev
        nc = children_size
        while true
          b = Aha.pointer @blocks, bi
          if b.value.num >= nc && nc < b.value.reject
            # 当前的block是合法的block
            e = b.value.ehead
            while true
              base = e ^ children_[0]
              (0...children_size).each do |i|
                c = children_[i]
                break unless Aha.at(@array, (base ^ c)).check < 0
                if i == children_size - 1
                  # 每个子节点都能插入，就这个block了。
                  # ehead 是，
                  b.value.ehead = e
                  return e
                end
              end
              # 因为空闲的 slot 是链表管理的，check直接就是下一个slot 了
              e = -Aha.at(@array, e).check
              if e == b.value.ehead
                # 已经找过一遍了
                break
              end
            end
          end
          # 当前数目的子节点已经不能在该block里面了。
          # 更新reject
          b.value.reject = nc
          if b.value.reject < @reject[b.value.num]
            @reject[b.value.num] = b.value.reject
          end
          bin = b.value.next
          b.value.trial = b.value.trial + 1 # 尝试失败的次数增加
          if b.value.trial == @max_trial
            # 尝试失败的次数太多，放入 C 队列
            transfer_block bi, pointerof(@bheadO), pointerof(@bheadC)
          end
          break if bi == bz
          bi = bin
        end
      end
      return add_block << 8
    end

    private def resolve(from_n : T, base_n : T, label_n : UInt8) : T
      to_pn = base_n ^ label_n
      from_p = Aha.at(@array, to_pn).check
      from_p_ptr = Aha.pointer @array, from_p
      from_n_ptr = Aha.pointer @array, from_n
      base_p = Aha.at(@array, from_p).base
      flag = consult from_n_ptr, from_p_ptr
      # 赶走child少的节点
      children_ = StaticArray(UInt8, 257).new(0_u8)
      if flag
        children_size = set_child base_n, from_n_ptr.value.child, label_n, true, children_.to_unsafe
      else
        children_size = set_child base_p, from_p_ptr.value.child, 255_u8, false, children_.to_unsafe
      end
      # 给被踢的children找好位置
      base = children_size == 1 ? find_place : find_places(children_.to_unsafe, children_size)
      base ^= children_[0]
      if flag
        from = from_n
        from_ptr = Aha.pointer @array, from_n
        base_ = base_n
      else
        from = from_p
        from_ptr = Aha.pointer @array, from_p
        base_ = base_p
      end
      if flag && children_[0] == label_n
        from_ptr.value.child = label_n
      end
      from_ptr.value.value = -base - 1
      # 任意被赶走的重新安置 child
      (0...children_size).each do |i|
        chl = children_[i]
        to = pop_enode base, chl, from # 新的位置
        to_ = base_ ^ chl              # 原来的位置
        n = Aha.pointer @array, to
        if i == children_size - 1
          n.value.sibling = 0_u8
        else
          n.value.sibling = children_[i + 1]
        end
        next if flag && to_ == to_pn # 这个节点没有子节点不需要下面的操作
        n_ = Aha.pointer @array, to_
        n.value.value = n_.value.value
        @leafs[n_.value.value] = to if n_.value.value >= 0 && n_.value.value != self.class.value_limit # 更新leaf节点信息
        n.value.flags = n_.value.flags
        if n.value.value < 0 && chl != 0
          # 更新孙子节点的父节点信息
          c = Aha.at(@array, to_).child
          Aha.at(@array, to).child = c
          ptr = Aha.pointer(@array, n.value.base ^ c)
          ptr.value.check = to
          c = ptr.value.sibling
          while c != 0
            ptr = Aha.pointer(@array, n.value.base ^ c)
            ptr.value.check = to
            c = ptr.value.sibling
          end
        end
        from_n = to if !flag && to_ == from_n
        if !flag && to_ == to_pn
          # 雀巢鸠占
          push_sibling from_n, to_pn ^ label_n, label_n, true
          to_ptr_ = Aha.pointer @array, to_
          to_ptr_.value.child = 0_u8
          n_.value.value = self.class.value_limit
          n_.value.check = from_n
        else
          push_enode to_
        end
      end
      return base ^ label_n if flag # 被赶走了
      return to_pn                  # 赶走了
    end

    def is_end?(id : T) : Bool
      return true if Aha.at(@array, id).end?
      Aha.at(@array, id).child == 0
    end

    protected def status
      nodes = 0
      keys = 0
      (0...@array.size).each do |i|
        node_ptr = Aha.pointer @array, i
        if n.value.occupy?
          nodes += 1
          if n.value >= 0
            keys += 1
          end
        end
      end
      return keys, nodes, @array_size
    end

    # jumpe 返回节点id
    private def jump(byte : UInt8, from : T = T.new(0)) : T
      from_ptr = Aha.pointer @array, from
      return T.new(-1) if from_ptr.value.value >= 0
      to = from_ptr.value.base ^ byte
      if Aha.at(@array, to).check != from
        return T.new(-1)
      end
      return to
    end

    private def jump(path : Bytes | Array(UInt8), from : T = 0) : T # 小于 0 说明没有路径
      path.each do |byte|
        from = jump byte, from
        return T.new(-1) if from < 0
      end
      return from
    end

    # yield 路上的节点
    private def jump(path : Bytes | Array(UInt8), from : T = 0, &block) : T # 小于 0 说明没有路径
      path.each_with_index do |byte, idx|
        from = jump byte, from
        return -1 if from < 0
        yield({from, idx})
      end
      return from
    end

    # 返回给定节点的到根节点的path
    private def key(id : T) : Array(UInt8)
      bytes = Array(UInt8).new
      while id > 0
        from = Aha.at(@array, id).check
        raise "no path" if from < 0
        chr = Aha.at(@array, from).base ^ id
        if chr != 0
          bytes << chr.to_u8
        end
        id = from
      end
      raise "invalid key" if id != 0 || bytes.size == 0
      bytes = bytes.reverse
      bytes << 0_u8
      return bytes
    end

    # 返回 这个节点的value值，已占用节点的value值就是key的idx
    # < 0 就是没有 value
    protected def value(id) : T
      ptr = Aha.pointer @array, id
      val = ptr.value.value
      return val if val >= 0
      to = ptr.value.base
      to_ptr = Aha.pointer @array, to
      return to_ptr.value.value if to_ptr.value.check == id && to_ptr.value.value >= 0 && to_ptr.value.value != self.class.value_limit
      return T.new(-1)
    end

    protected def has_value?(id) : Bool
      ptr = Aha.pointer @array, id
      val = ptr.value.value
      return true if val >= 0
      to = ptr.value.base
      to_ptr = Aha.pointer @array, to
      return true if to_ptr.value.check == id && to_ptr.value.value >= 0
      return false
    end

    # 根据id获得string
    def [](sid : Int) : String
      String.new key(@leafs[T.new(sid)]).to_unsafe # @TODO
    end

    def insert(key : String) : T
      insert key.bytes
    end

    def insert(key : Bytes | Array(UInt8)) : T
      p = get key, T.new(0), T.new(0) # 创建节点
      id = T.new(@leaf_size)          # @TODO 替代 array后换掉
      p_ptr = Aha.pointer(@array, p)
      return p_ptr.value.value if p_ptr.value.end? && p_ptr.value.value != self.class.value_limit
      p_ptr.value.value = id # 设置 id
      p_ptr.value.end!
      if @key_num == @key_capacity
        @key_capacity *= 2
        @leafs = @leafs.realloc(@key_capacity)
      end
      @leafs[@leaf_size] = p
      @leaf_size += 1
      @key_num += 1
      return id
    end

    def delete(key : String) : T
      delete key.bytes
    end

    # 返回 被删除的id, 如果 < 0 就是没有这个key
    def delete(key : Bytes | Array(UInt8)) : T
      to = jump key, T.new(0)
      return T.new(-1) if to < 0
      vk = value to
      return T.new(-1) if vk < 0
      to_ptr = Aha.pointer @array, to
      if to_ptr.value.value < 0
        base = to_ptr.value.base
        if Aha.at(@array, base).check == to
          to = base
        end
      end
      while true
        to_ptr = Aha.pointer @array, to
        from = to_ptr.value.check
        from_ptr = Aha.pointer @array, from
        base = from_ptr.value.base
        label = (to ^ base).to_u8
        if to_ptr.value.sibling != 0 || from_ptr.value.child != label
          pop_sibling from, label
          push_enode to
          break
        end
        push_enode to
        to = from
      end
      @key_num -= 1
      @leafs[vk] = T.new(-1)
      return vk
    end

    def []?(key : String) : T?
      self[key.to_slice]?
    end

    # 返回 -1
    def []?(key : Bytes | Array(UInt8)) : T?
      to = jump key, T.new(0)
      return nil if to < 0
      vk = value to
      return nil if vk < 0
      return vk
    end

    def [](key : Bytes | Array(UInt8) | String) : T
      ret = self[key]?
      raise IndexError.new if ret.nil?
      return ret
    end

    # 返回key的所有前缀
    # yield value
    def prefix_match(key : Bytes | Array(UInt8), num : T)
      from = 0
      key.each_with_index do |k, i|
        to = jump(k, from)
        break if to < 0
        vk = value to
        if vk >= 0
          yield vk
          num -= 1
          break if num == 0
        end
        from = to
      end
    end

    # 返回以 key 为前缀的字符串
    def prefix_predict(key : Bytes | Array(UInt8), num : T)
      root = jump key, 0
      return if root < 0
      from = self.begin root
      while true
        return if from < 0
        yield value from
        from = self.next from, root
      end
    end

    # 返回终止节点
    private def begin(from : T) : T
      from_ptr = Aha.pointer @array, from
      c = from_ptr.value.child
      while c != 0
        to = from_ptr.value.base ^ c
        c = Aha.at(@array, to).child
        from = to
        from_ptr = Aha.pointer @array, from
      end
      return from_ptr.value.base if from_ptr.value.base > 0
      return from
    end

    # 尝试寻找兄弟节点，父节点的兄弟节点，
    private def next(from : T, root : T)
      from_ptr = Aha.pointer @array, from
      c = from_ptr.value.sibling
      while c == 0 && from != root && from_ptr.value.check >= 0
        from = from_ptr.value.check
        c = from_ptr.value.sibling
        from_ptr = Aha.pointer @array, from
      end
      return -1 if from == root
      from = Aha.at(@array, from_ptr.value.check).base ^ c
      return self.begin(from)
    end

    def bfs_each(&block)
      byte_bfs_each do |bytes, id|
        yield({String.new(bytes.to_unsafe), id})
      end
    end

    def dfs_each(&block)
      byte_dfs_each do |bytes, id|
        yield({String.new(bytes.to_unsafe), id})
      end
    end

    def byte_each(&block)
      (0...@leaf_size).each do |id|
        lnode = @leafs[id]
        yield({key(lnode), T.new(id)}) if id >= 0 # @TODO 替换 array 后, 替换
      end
    end

    def each(&block)
      byte_each do |bytes, id|
        yield({String.new(bytes.to_unsafe), id})
      end
    end

    def byte_bfs_each(&block)
      queue = Deque(T).new
      queue << T.new(0)
      while queue.size > 0
        node = queue.shift
        yield({key(node), value(node)}) if has_value?(node)
        children(node) do |n|
          queue << n.id
        end
      end
    end

    def byte_dfs_each(&block)
      stack = Array(T).new
      stack << T.new(0)
      while stack.size > 0
        node = stack[-1]
        if has_value?(node)
          yield({key(node), value(node)})
        end
        first_child_ = first_child node
        if first_child_
          stack << first_child_.id
          next
        end
        sibling_ = sibling stack[-1]
        while sibling_.nil?
          stack.pop
          return if stack.empty?
          sibling_ = sibling stack[-1]
        end
        stack[-1] = sibling_.id
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

    private def jump(chr : Char, from : T = T.new(0)) : T # 小于 0 说明没有路径
      chr.each_byte do |byte|
        from = jump byte, from
        return T.new(-1) if from < 0
      end
      return from
    end

    # yield string_id, consumed_char_num
    def exact(s : String, ignore_case : Bool, limit : Int32 = -1)
      return if limit == 0
      queue = [T.new(0)] # queue of node_id
      new_queue = [] of T
      char_num = 0
      s.each_char do |chr|
        char_num += 1
        other_char = chr
        other_char = chr.uppercase? ? chr.downcase : chr.upcase if ignore_case
        queue.each do |node|
          new_node = jump chr, node
          new_queue << new_node if new_node >= 0
          if ignore_case && chr != other_char
            new_node = jump other_char, node
            new_queue << new_node if new_node >= 0
          end
        end
        new_queue, queue = queue, new_queue
        new_queue.clear
      end
      num = 0
      queue.each do |to|
        break if limit >= 0 && num >= limit
        vk = value to
        yield({vk, char_num}) if vk >= 0
        num += 1
      end
    end

    {% for name, idx in ["String", "Array(Char)", "Slice(Char)"] %}
    def prefix(s : {{name.id}}, ignore_case : Bool, limit : Int32 = -1)
      return if limit == 0
      queue = [T.new(0)] # queue of node_id
      new_queue = [] of T
      char_num = 0
      num = 0
      s.each{{name == "String" ? "_char".id : "".id}} do |chr|
        char_num += 1
        other_char = chr
        other_char = chr.uppercase? ? chr.downcase : chr.upcase if ignore_case
        queue.each do |node|
          new_node = jump chr, node
          if new_node >= 0
            new_queue << new_node
            vk = value new_node
            if vk >= 0
              yield({vk, char_num})
              num += 1
              break if limit >= 0 && num >= limit
            end
          end
          if ignore_case && other_char != chr
            new_node = jump other_char, node
            if new_node >= 0
              new_queue << new_node
              vk = value new_node
              if vk >= 0
                yield({vk, char_num})
                num += 1
                break if limit >= 0 && num >= limit
              end
            end
          end
        end
        new_queue, queue = queue, new_queue
        new_queue.clear
      end
    end
    {% end %}

    #  bfs 的顺序输出的
    def predict(s : String, ignore_case : Bool, limit : Int32 = -1)
      return if limit == 0
      queue = [T.new(0)] # queue of node_id
      new_queue = [] of T
      char_num = 0
      s.each_char do |chr|
        char_num += 1
        other_char = chr
        other_char = chr.uppercase? ? chr.downcase : chr.upcase if ignore_case
        queue.each do |node|
          new_node = jump chr, node
          new_queue << new_node if new_node >= 0
          if ignore_case
            new_node = jump other_char, node
            new_queue << new_node if new_node >= 0
          end
        end
        new_queue, queue = queue, new_queue
        new_queue.clear
      end
      num = 0
      while !queue.empty?
        queue.each do |to|
          vk = value to
          yield({vk, char_num}) if vk >= 0
          num += 1
          break if limit >= 0 && num >= limit
          children(to) do |nd|
            new_queue << nd.id
          end
        end
        break if limit >= 0 && num >= limit
        new_queue, queue = queue, new_queue
        new_queue.clear
      end
    end
  end
end
