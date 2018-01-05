module Aha
  class DAC
    # dynamic ac, 空间使用差一点
    # 能够动态往自动机中加pattern
    # 目前不支持 Byte 级别

    # 根据 SAM(D), 将 AC(D) 更新为 AC(D'), 花费与需要更新的state的数目linear大小的时间
    # 将 DAWG(D) 更新为 DAWG(D'), 花费 O(mlog\sigma) m 为加入的pattern的长度，sigma是字母表大小

    # 利用的性质 s' = flink(s) 当且仅当 s' = slink^k(s), 这个是显然的

    # An edge e from [x]D to [xc]D labeled by c is a primary edge
    # if both x and xc are the longest string in their equivalence classes,
    # otherwise it is a secondary edge.
    @[Flags]
    enum EdgeType
      Primary   # sa 的 primary
      Secondary # sa 的 secondary
      Trie      # trie树上的边
      def self.trie
        Trie
      end

      def self.secondary
        Secondary
      end

      def self.primary
        Primary
      end

      def to_io(io, format)
        to_i32.to_io io, format
      end

      def self.from_io(io, format)
        self.from_value Int32.from_io(io, format)
      end
    end

    struct Edge
      @sink : Int32
      @flags : EdgeType

      getter :sink, :flags

      def initialize(@sink, @flags)
      end

      def to_io(io : IO, format : IO::ByteFormat)
        @sink.to_io io, format
        @flags.to_io io, format
      end

      def self.from_io(io : IO, format : IO::ByteFormat) : self
        sink = Int32.from_io io, format
        flags = EdgeType.from_io io, format
        return Edge.new(sink, flags)
      end

      delegate :trie?, to: @flags
      delegate :primary?, to: @flags
      delegate :secondary?, to: @flags

      def sam?
        primary? || secondary?
      end
    end

    struct State
      @len : Int32
      @next : Hash(Char, Edge) # sam 的 next
      @slink : Int32           # 不在同一个right class的最长的suffix的class
      @flink : Int32           # fail
      @trunk : Bool            # trie 树上的 node
      @slink_idx : Int32       # slink的reverse_slink数组当中的第几个
      @reverse_slink : Array(Int32)

      @output : Int32
      @output_next : Int32

      getter :next, :trunk, :len
      property :output, :flink, :slink, :slink_idx, :output_next

      # from a property of the DAWG constructing algorithm,
      # the number of suffix links that point at each node is never reduced.
      # thus the size of array storing inverse suffix links from the node is also never reduced.
      # we do not have to worry about deleting any elements from the array.
      # each inverse suffix link is updated only when the node is split
      # P114

      def initialize(@len,
                     @slink = -1,
                     @next = {} of Char => Edge,
                     @flink = -1,
                     @output = -1,
                     @output_next = -1,
                     @trunk = true,
                     @slink_idx = -1,
                     @reverse_slink = [] of Int32)
      end

      def to_io(io : IO, format : IO::ByteFormat)
        @len.to_io io, format
        Aha.hash_to_io(@next, Char, Edge, io, format)
        @slink.to_io io, format
        @flink.to_io io, format
        (@trunk ? 1 : 0).to_io io, format
        @slink_idx.to_io io, format
        Aha.array_to_io(@reverse_slink, Int32, io, format)
        @output.to_io io, format
        @output_next.to_io io, format
      end

      def self.from_io(io : IO, format : IO::ByteFormat) : self
        len = Int32.from_io io, format
        next_ = Aha.hash_from_io(Char, Edge, io, format)
        slink = Int32.from_io io, format
        flink = Int32.from_io io, format
        trunk = (Int32.from_io io, format) == 1
        slink_idx = Int32.from_io io, format
        reverse_slink = Aha.array_from_io(Int32, io, format)
        output = Int32.from_io io, format
        output_next = Int32.from_io io, format
        return State.new(len,
          slink,
          next_,
          flink,
          output,
          output_next,
          trunk,
          slink_idx,
          reverse_slink)
      end

      def isuf
        @reverse_slink
      end
    end

    @states : Array(State)
    @key_num : Int32

    def to_io(io : IO, format : IO::ByteFormat)
      Aha.array_to_io @states, State, io, format
      @key_num.to_io io, format
    end

    def self.from_io(io : IO, format : IO::ByteFormat) : self
      states = Aha.array_from_io State, io, format
      key_num = Int32.from_io io, format
      return DAC.new(states, key_num)
    end

    def self.compile(keys : Array(String)) : DAC
      dac = DAC.new
      keys.each do |key|
        dac.insert key
      end
      dac
    end

    private def sa_edges(nid) : Hash(Char, Edge)
      Aha.at(@states, nid).next
    end

    private def sa_edge(nid, chr) : Edge?
      sa_edges(nid)[chr]?
    end

    private def sa_end?(nid) : Bool
      Aha.at(@states, nid).output >= 0
    end

    private def sa_edge_secondary_to_primary(parent, child, chr)
      edge = sa_edge(parent, chr)
      Aha.at(@states, parent).next[chr] = Edge.new edge.sink, (edge.flags | EdgeType::Primary) & (~EdgeType::Secondary)
    end

    private def sa_edge_set_sink(parent, child, chr)
      edge = sa_edge(parent, chr)
      Aha.at(@states, parent).next[chr] = Edge.new child, edge.flags
    end

    {% for name, index in [:output, :flink, :slink, :trunk, :len, :output_next] %}
      private def sa_set_{{name.id}}(nid, val)
        Aha.at(@states, nid).{{name.id}} = val
      end
      private def sa_{{name.id}}(nid)
        Aha.at(@states, nid).{{name.id}}
      end
    {% end %}

    private def sa_isuf(nid, &block)
      Aha.at(@states, nid).isuf.each do |r|
        yield r
      end
    end

    {% for name, index in [:trie, :primary, :secondary, :sam] %}
      private def sa_{{name.id}}_edge(nid, chr) : Edge?
        edge = sa_edge(nid, chr)
        return nil unless edge
        return nil if edge.{{name.id}}?
        return edge
      end

      private def sa_set_{{name.id}}_edge(nid, chr, child)
        Aha.at(@states, nid).next[chr] = Edge.new(child, EdgeType.{{name.id}})
      end
    {% end %}

    def initialize
      @states = [State.new(0)]
      @key_num = 0
    end

    protected def initialize(@states, @key_num)
    end

    def root
      0
    end

    def insert(key : String) : Int32
      key_id = @key_num
      active_state = root
      new_states = Array(Int32).new
      # 将新的key插入，得到有哪些新的状态
      key.each_char_with_index do |chr, idx|
        edge = sa_trie_edge(active_state, chr)
        if !edge.nil?
          acitve_state = edge.sink
        else
          active_state_ = @states.size
          @states << State.new(idx + 1)
          sa_set_trie_edge(active_state, chr, active_state_)
          new_states << active_state_
          acitve_state = active_state_
        end
      end

      sa_set_output(active_state, key_id)
      @key_num += 1

      fail_states = get_fail_states key, key.size - new_states.size + 1
      fail_states.each do |s, i|
        sa_set_flink(s, new_states[i - new_states.size + 1])
      end
      active_state = root
      key.each_char_with_index do |chr, idx|
        sink = sa_trie_edge(active_state, chr).not_nil!.sink
        if new_states.includes? sink
          failure_state = sa_flink(active_state)
          while sa_trie_edge(failure_state, chr).nil?
            failure_state = sa_flink(failure_state)
          end
          active_state = sa_trie_edge(active_state, chr).not_nil!.sink
          sa_set_flink(active_state, failure_state)
        else
          active_state = sink
        end
      end
      key_id
    end

    private def match_(key : String)
      state = root
      key.each_char_with_index do |chr, i|
        while true
          edge_to_child = sa_trie_edge(state, chr)
          unless edge_to_child.nil?
            state = edge_to_child.sink
            yield i, state if sa_end?(state)
            break
          end
          break if state == root
          state = sa_flink(state)
        end
      end
    end

    def match(key : String, &block)
      match_ key do |idx, state|
        while state && sa_end?(state)
          val = sa_output(state)
          len = sa_len(state)
          start_offset = idx - len + 1
          end_offset = idx + 1
          yield AC::Hit.new(start_offset, end_offset, val)
          state = sa_output_next(state)
        end
      end
    end

    def sa_extend(active_node, chr)
      edge = sa_sam_edge(active_node, chr)
      if !edge.nil?
        if edge.primary?
          return edge.sink
        else
          return split active_node, edge.sink, chr
        end
      else
        new_active_node = State.new # @TODO len 需要被设置
        sa_set_primary_edge(active_node, chr, new_active_node)
        current_node = active_node
        suffix_node = nil
        while current_node != root && suffix_node.nil?
          current_node = sa_slink(current_node)
          edge = sa_primary_edge current_node, chr
          if !edge.nil?
            suffix_node = ege.sink
          else
            edge = sa_secondary_edge current_node, chr
            if !edge.nil?
              child_node = edge.sink
              suffix_node = split current_node, child_node, chr
            else
              sa_secondary_edges(current_node, chr, new_active_node)
            end
          end
        end
        suffix_node = source if suffix_node.nil?
        set_slink(new_active_node, suffix_node)
        return new_active_node
      end
    end

    def split(parent_node, child_node, chr)
      new_child_node = State.new # TODO @len
      # Make the secondaryedgefrom parentnode to childnode into a primary edge
      # from parentnode to newchildnode (with the samelabel).
      sa_edge_secondary_to_primary parent_node, new_child_node, chr

      # For every primary and secondary outgoing edge of childnode,
      # create a secondary outgoing edge of new childnode with the same label
      # and leading to the samenode.
      sa_edges(child_node).each do |chr, edge|
        if edge.sam?
          sa_edges(new_child_node)[chr] = Edge.new(edge.sink, edge.flags)
        end
      end
      # Setthe suffix pointer of newchildnode equal to that of childnode.
      sa_set_slink(new_child_node, sa_slink(child_node))
      # Reset the suffix pointer of childnode to point to newchildnode.
      sa_set_slink(child_node, new_child_node)
      current_node = parent_node
      while current_node != root
        current_node = sa_slink(current_node)
        edges = Array(Tuple(Char, Edge)).new
        sa_edges(current_node).each do |chr, edge|
          if edge.sink == child_node && edge.secondary?
            sa_edge_set_sink current_node, new_child_node, chr
          else
            break
          end
        end
      end
      return new_child_node
    end

    def get_fail_states(key : String, start : Int32) : Array(Tuple(Int32, Int32))
      fail_states = Array(Tuple(Int32, Int32)).new
      stack = Array(Tuple(Int32, Int32)).new
      active_node = root
      key.each_char_with_index do |chr, idx|
        edge = sa_trie_edge(active_node, chr)
        break if edge.nil?
        if idx >= start
          stack << ({edge.sink, idx})
        end
      end
      marked = Set(Int32).new
      while !stack.empty?
        active_node, i = stack.pop
        queue = Deque(Int32).new
        queue << active_node
        while !queue.empty?
          node = queue.shift
          unless marked.includes? node
            marked << node
            if sa_trunk(node)
              fail_states << ({node, i})
            else
              sa_isuf(node) do |lnode|
                queue << lnode
              end
            end
          end
        end
      end
      return fail_states
    end

    def save(path)
      File.open(path, "wb") do |f|
        to_io f, IO::ByteFormat::LittleEndian
      end
    end

    def self.load(path)
      File.open(path, "rb") do |f|
        return self.from_io f, IO::ByteFormat::LittleEndian
      end
    end
  end
end
