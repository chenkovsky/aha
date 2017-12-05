class Aha
  class Cedar
    VALUE_LIMIT = (1 << 31) - 1

    struct Node
      @value : Int32
      @check : Int32

      property :value, :check

      def initialize(@value, @check)
      end

      def base
        -(@value + 1)
      end
    end

    struct NodeDesc
      @label : UInt8
      @id : Int32

      property :label, :id

      def initialize(@label, @id)
      end
    end

    struct NodeInfo
      @sibling : UInt8
      @child : UInt8
      @end : Bool
      property :child, :sibling, :end

      def initialize(@sibling, @child, @end)
      end
    end

    struct Block
      @prev : Int32
      @next : Int32
      @num : Int32
      @reject : Int32
      @trial : Int32
      @ehead : Int32

      property :prev, :next, :num, :reject, :trial, :ehead

      def initialize(@prev, @next, @trial, @ehead, @num = 256, @reject = 257)
      end
    end

    @array : Array(Node)
    @infos : Array(NodeInfo)
    @blocks : Array(Block)
    @key_lens : Array(Int32)
    @reject : Array(Int32)
    @bheadF : Int32
    @bheadC : Int32
    @bheadO : Int32
    @size : Int32
    @ordered : Bool
    @max_trial : Int32

    protected getter :array

    def initialize(@ordered = false)
      capacity = 256
      @key_lens = Array(Int32).new
      @array = Array(Node).new(capacity)
      @infos = Array(NodeInfo).new(capacity)
      @blocks = Array(Block).new
      @size = capacity
      @max_trial = 1
      @array << Node.new(-2, 0)
      (1...256).each { |i| @array << Node.new(-(i - 1), -(i + 1)) }
      @array[1].value = -255
      @array[255].check = -1
      @blocks << Block.new(0, 0, 0, 1)
      @reject = (0..256).map { |i| i + 1 }
      @bheadF = 0
      @bheadC = 0
      @bheadO = 0
    end

    def key_len(key : Int32) : Int32
      @key_lens[key]
    end

    # 从 key 的 start 位开始, 从 from 节点开始遍历，如果没有节点就创建节点, 返回最终的叶子节点
    private def get(key : Bytes | Array(UInt8), from : Int32, start : Int32) : Int32
      (start...key.size).each do |pos|
        value = @array[from].value
        if value >= 0 && value != VALUE_LIMIT
          # 每个节点的都添加一个label=0的子节点
          # 这个子节点的, label = 0 表示完整的匹配
          # 人为增加一个叶子节点
          to = follow(from, 0_u8)
          @array[to].value = value
        end
        from = follow(from, key[pos])
      end
      # value < 0 时 base >= 0, 说明不是叶子节点
      # value >= 0 时 base < 0, 说明是叶子节点
      @array[from].value < 0 ? follow(from, 0_u8) : from
    end

    # 从 from 开始，如果没有label的子节点，那么创建，返回子节点的id
    private def follow(from : Int32, label : UInt8) : Int32
      base = @array[from].base
      to = base ^ label
      if base < 0 || @array[to].check < 0
        # 当前节点没有子节点 || 需要存放的地方没有被占用。
        # has_child 当前节点是否还有其他节点
        has_child = base >= 0 && @array[base ^ @infos[from].child.to_i32].check == from
        to = pop_enode base, label, from
        # 添加当前的子节点
        push_sibling from, to ^ label.to_i32, label, has_child
      elsif @array[to].check != from
        # 需要存放的地方已经被占用了
        to = resolve from, base, label
      end
      to
    end

    # 将 block bi 从双向列表中拿出
    private def pop_block(bi : Int32, head_in : Pointer(Int32), last : Bool) : Void
      if last
        head_in.value = 0
      else
        b = @blocks.to_unsafe + bi
        @blocks[b.value.prev].next = b.value.next
        @blocks[b.value.next].prev = b.value.prev
        if bi == head_in.value
          # 如果双向列表的头 是 bi 那么应该将头设为bi的next
          head_in.value = b.value.next
        end
      end
    end

    # 将 bi 放入双向列表
    private def push_block(bi : Int32, head_out : Pointer(Int32), empty : Bool) : Void
      b = @blocks.to_unsafe + bi
      if empty
        head_out.value, b.value.prev, b.value.next = bi, bi, bi
      else
        tail_out = @blocks.to_unsafe + head_out.value
        b.value.prev = tail_out.value.prev
        b.value.next = head_out.value
        head_out.value, tail_out.value.prev, @blocks[tail_out.value.prev].next = bi, bi, bi
      end
    end

    # 增加一个可用的block, 返回 block 的 id
    private def add_block : Int32
      @blocks << Block.new(0, 0, 0, @size)
      @array << Node.new(-(@size + 255), -(@size + 1))
      ((@size + 1)...(@size + 255)).each do |i|
        @array << Node.new(-(i - 1), -(i + 1))
      end
      @array << Node.new(-(@size + 254), -@size)
      push_block @size >> 8, pointerof(@bheadO), @bheadO == 0
      @size += 256
      @size >> 8 - 1
    end

    # 将 block 放入另一个队列
    private def transfer_block(bi : Int32, head_in : Pointer(Int32), head_out : Pointer(Int32))
      pop_block bi, head_in, bi == @blocks[bi].next
      push_block bi, head_out, head_out.value == 0 && @blocks[bi].num != 0
    end

    # 找到一个空的节点，返回节点 id
    # from 为 父节点， base 为该父节点的 base
    private def pop_enode(base : Int32, label : UInt8, from : Int32) : Int32
      e = base ^ label
      e = find_place if base < 0 # 如果还没有任何子节点，给其找个位置
      bi = e >> 8
      n = @array.to_unsafe + e
      b = @blocks.to_unsafe + bi
      b.value.num -= 1 # 该block中剩余的slot数目减少
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
        @array[-n.value.value].check = n.value.check
        @array[-n.value.check].value = n.value.value
        if e == b.value.ehead
          b.value.ehead = -n.value.check
        end
        if bi != 0 && b.value.num == 1 && b.value.trial != @max_trial
          # 如果只有一个slot了，那么从 O 队列放入 C 队列
          transfer_block bi, pointerof(@bheadO), pointerof(@bheadC)
        end
      end
      n.value.value = VALUE_LIMIT
      n.value.check = from
      @array[from].value = -(e ^ label) - 1 if base < 0
      e
    end

    private def push_enode(e : Int32)
      bi = e >> 8
      b = @blocks.to_unsafe + bi
      b.value.num += 1
      if b.value.num == 1
        # 如果 block 中原来没有slot。现在有了
        # 从 F 链 放入 C 链
        b.value.ehead = e
        @array[e] = Node.new(-e, -e)
        transfer_block bi, pointerof(@bheadF), pointerof(@bheadC) unless bi == 0
      else
        # 原本就有， 首先放入队列
        prev = b.value.ehead
        next_ = -@array[prev].check
        @array[e] = Node.new(-prev, -next_)
        @array[prev].check = -e
        @array[next_].value = -e
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
      @infos[e] = NodeInfo.new(0_u8, 0_u8, false)
    end

    # 将 label 作为子节点， 在已经分配好空间的情况下，调用次函数
    private def push_sibling(from : Int32, base : Int32, label : UInt8, has_child : Bool)
      c = @infos.to_unsafe + from
      keep_order = c.value.child == 0
      if @ordered
        keep_order = label > c.value.child
      end
      if has_child && keep_order
        c = @infos.to_unsafe + (base ^ c.value.sibling.to_i32)
        while @ordered && c.value.sibling != 0 && c.value.sibling < label
          c = @infos.to_unsafe + (base ^ c.value.sibling.to_i32)
        end
      end
      # 加入 sibling 的链表
      @infos[base ^ label.to_i32].sibling = c.value.sibling
      c.value.sibling = label
    end

    # 将 label 节点从 sibling 链表移出
    private def pop_sibling(from : Int32, base : Int32, label : UInt8)
      c = pointerof(@infos[from].child)
      while c.value != label
        c = pointerof(@infos[base ^ c.value.to_i32]).sibling
      end
      c.value = @infos[base ^ c.value.to_i32].sibling
    end

    # cp 是否比 cn sibling 多
    private def consult(basen : Int32, basep : Int32, cn : UInt8, cp : UInt8) : Bool
      cn = @infos[basen ^ cn.to_i32].sibling
      cp = @infos[basep ^ cp.to_i32].sibling
      while cn != 0 && cp != 0
        cn = @infos[basen ^ cn.to_i32].sibling
        cp = @infos[basep ^ cp.to_i32].sibling
      end
      cp != 0
    end

    def has_label?(id : Int32, label : UInt8) : Bool
      child(id, label) >= 0
    end

    # 返回 node 的 id
    def child(id : Int32, label : UInt8) : Int32 # < 0 说明不存在
      base = @array[id].base
      cid = base ^ label.to_i32
      if cid < 0 || cid >= @size || @array[cid].check != id
        return -1
      end
      return cid
    end

    # yield 所有子节点的NodeDesc
    def childs(id : Int32)
      base = @array[id].base
      s = @infos[id].child
      if s == 0 && base > 0
        s = @infos[base].sibling
      end
      while s != 0
        to = base ^ s.to_i32
        break if to < 0
        yield NodeDesc.new(id: to, label: s)
        s = @infos[to].sibling
      end
    end

    def childs(id : Int32) : Array(NodeDesc)
      req = [] of NodeDesc
      childs.each do |c|
        req << c
      end
      return req
    end

    # c 是 base的第一个child
    # label 是需要加入的child
    # 返回所有child的label的数组
    private def set_child(base : Int32, c : UInt8, label : UInt8, flag : Bool) : Array(UInt8)
      child = Array(UInt8).new(257)
      if c == 0
        child << c
        c = @infos[base ^ c.to_i32].sibling
      end
      if @ordered
        while c != 0 && c <= label
          child << c
          c = @infos[base ^ c.to_i32].sibling
        end
      end
      if flag
        child << label
      end
      while c != 0
        child << c
        c = @infos[base ^ c.to_i32].sibling
      end
      child
    end

    # 找一个位置
    def find_place : Int32
      return @blocks[@bheadC].ehead if @bheadC != 0
      return @blocks[@bheadO].ehead if @bheadO != 0
      return add_block << 8
    end

    # 给所有的 child 找位置
    def find_places(child : Array(UInt8)) : Int32
      bi = @bheadO
      if bi != 0
        bz = @blocks[@bheadO].prev
        nc = child.size
        while true
          b = @blocks.to_unsafe + bi
          if b.value.num >= nc && nc < b.value.reject
            # 当前的block是合法的block
            e = b.value.ehead
            while true
              base = e ^ child[0].to_i32
              i = 0
              child.each_with_index do |c, i|
                break if @array[base ^ c.to_i32].check < 0
                if i == child.size - 1
                  # 每个子节点都能插入，就这个block了。
                  # ehead 是，
                  b.value.ehead = e
                  return e
                end
              end
              # 因为空闲的 slot 是链表管理的，check直接就是下一个slot 了
              e = -@array[e].check
              if e == b.value.ehead
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
          b.value.trial += 1 # 尝试失败的次数增加
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

    private def resolve(from_n : Int32, base_n : Int32, label_n : UInt8) : Int32
      to_pn = base_n ^ label_n.to_i32
      from_p = @array[to_pn].check
      base_p = @array[from_p].base
      flag = consult base_n, base_p, @infos[from_n].child, @infos[from_p].child
      # 赶走child少的节点
      if flag
        children = set_child base_n, @infos[from_n].child, label_n, true
      else
        children = set_child base_p, @infos[from_p].child, 255_u8, false
      end
      # 给被踢的children找好位置
      base = children.size == 1 ? find_place : find_places(children)
      base ^= children[0].to_i32
      if flag
        from = from_n
        base_ = base_n
      else
        from = from_p
        base_ = base_p
      end
      if flag && children[0] == label_n
        @infos[from].child = label_n
      end
      @array[from].value = -base - 1
      # 任意被赶走的重新安置 child
      children.each_with_index do |chl, i|
        to = pop_enode base, chl, from # 新的位置
        to_ = base_ ^ chl.to_i32       # 原来的位置
        if i == children.size - 1
          @infos[to].sibling = 0_u8
        else
          @infos[to].sibling = children[i + 1]
        end
        next if flag && to_ == to_pn # 这个节点没有子节点不需要下面的操作
        n = @array.to_unsafe + to
        n_ = @array.to_unsafe + to_
        n.value.value = n_.value.value
        if n.value.value < 0 && chl != 0
          # 这个节点有子节点，需要修改check
          c = @infos[to_].child
          @infos[to].child = c
          @array[n.value.base ^ c.to_i32].check = to
          c = @infos[n.value.base ^ c.to_i32].sibling
          while c != 0
            @array[n.value.base ^ c.to_i32].check = to
            c = @infos[n.value.base ^ c.to_i32].sibling
          end
        end
        from_n = to if !flag && to_ == from_n
        if !flag && to_ == to_pn
          # 雀巢鸠占
          push_sibling from_n, to_pn ^ label_n.to_i32, label_n, true
          @infos[to_].child = 0_u8
          n_.value.value = VALUE_LIMIT
          n_.value.check = from_n
        else
          push_enode to_
        end
      end
      return base ^ label_n.to_i32 if flag # 被赶走了
      return to_pn                         # 赶走了
    end

    def is_end?(id : Int32) : Bool
      return true if @infos[id].end
      @infos[id].child == 0
    end

    def status
      @array.each_with_index do |n, i|
        nodes = 0
        keys = 0
        if n.check >= 0
          nodes += 1
          if n.value >= 0
            keys += 1
          end
        end
      end
      return keys, nodes, @size
    end

    # jumpe 返回节点id
    private def jump(byte : UInt8, from : Int32) : Int32
      return -1 if @array[from].value >= 0
      to = @array[from].base ^ byte.to_i32
      if @array[to].check != from
        return -1
      end
      return to
    end

    private def jump(path : Bytes | Array(UInt8), from : Int32) : Int32 # 小于 0 说明没有路径
      path.each do |byte|
        from = jump byte, from
        return -1 if from < 0
      end
      return to
    end

    # 返回给定节点的到根节点的path
    private def key(id : Int32) : Array(Byte)
      bytes = Array(UInt8).new
      while id > 0
        from = @array[id].check
        raise "no path" if from < 0
        chr = @array[from].base ^ id
        if chr != 0
          key << chr
        end
        id = from
      end
      raise "invalid key" if id != 0 || key.size == 0
      return key.reverse
    end

    # 返回 这个节点的value值，已占用节点的value值就是key的idx
    protected def vkey(id) : Int32
      val = @array[id].value
      return val if val >= 0
      to = @array[id].base
      return @array[to].value if @array[to].check == id && @array[to].value >= 0
      raise "no value"
    end

    def insert(key : String) : Int32
      insert key.bytes
    end

    def insert(key : Bytes | Array(UInt8)) : Int32
      p = get key, 0, 0 # 创建节点
      id = @key_lens.size
      @array[p].value = id # 设置 id
      @infos[p].end = true
      @key_lens << key.size
      return id
    end

    # 返回 被删除的节点, 如果 < 0 就是没有这个key
    def delete(key : Bytes | Array(UInt8)) : Int32
      to = jump key, 0
      return -1 if to < 0
      if @array[to].value < 0
        base = @array[to].base
        if @array[base].check == to
          to = base
        end
      end
      while true
        from = @array[to].check
        base = @array[from].base
        label = (to ^ base).to_u8
        if @infos[to].sibling != 0 || @infos[from].child != label
          pop_sibling from, base, label
          push_encode to
          break
        end
        push_encode to
        to = from
      end
    end

    # 返回 -1
    def []?(key : Bytes | Array(UInt8)) : Int32?
      to = jump key, 0
      return nil if to < 0
      vk = vkey to
      return nil if vk < 0
      return vk
    end

    def [](key : Bytes | Array(UInt8)) : Int32
      ret = self[key]
      raise IndexError.new if ret < 0
      return ret
    end

    # 返回key的所有前缀
    # yield vkey
    def prefix_match(key : Bytes | Array(UInt8), num : Int32)
      from = 0
      key.each_with_index do |k, i|
        to = jump(k, from)
        break if to < 0
        vk = vkey to
        if vk >= 0
          yield vk
          num -= 1
          break if num == 0
        end
        from = to
      end
    end

    # 返回以 key 为前缀的字符串
    def prefix_predict(key : Bytes | Array(UInt8), num : Int32)
      root = jump key, 0
      return if root < 0
      from = self.begin root
      while true
        return if from < 0
        yield vkey from
        from = self.next from, root
      end
    end

    # 返回终止节点
    private def begin(from : Int32) : Int32
      c = @infos[from].child
      while c != 0
        to = @array[from].base ^ c.to_i32
        c = @infos[to].child
        from = to
      end
      return @array[from].base if @array[from].base > 0
      return from
    end

    # 尝试寻找兄弟节点，父节点的兄弟节点，
    private def next(from : Int32, root : Int32)
      c = @infos[from].sibling
      while c == 0 && from != root && @array[from].check >= 0
        from = @array[from].check
        c = @infos[from].sibling
      end
      return -1 if from == root
      from = @array[@array[from].check].base ^ c.to_i32
      return self.begin(from)
    end
  end
end
