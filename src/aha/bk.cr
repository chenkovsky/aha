module Aha
  class BKTree(T)
    @dist_func : (T, T) -> Int32

    struct Node(T)
      @term : T
      @children : Hash(Int32, T)

      def initialize(@term, @children = {} of Int32 => T)
      end
    end

    @nodes : Array(Node(T))

    def initialize(@nodes = [] of Node(T), &dist_func)
      @dist_func = dist_func
    end

    def insert(key : T)
      if @nodes.empty?
        @nodes << Node.new(key)
      else
        cur_node = @nodes[0]
        while true
          score = @dist_func.call(cur_node, key)
          break if score == 0
          if child = cur_node.children[score]?
            cur_node = child
          else
            cur_node.children[score] = Node.new(key)
            break
          end
        end
      end
    end

    def <<(key : T)
      insert key
    end

    def match(term : T, threshold = 0, &block : T, Int32 -> Void)
      return if @nodes.empty?
      queue = Deque(Node(T)).new
      queue << @nodes[0]
      while !queue.empty?
        cur = queue.shift
        dist = @dist_func.call(cur.term, term)
        yield cur, dist
        (-threshold..threshold).each do |d|
          child = cur.children[d + dist]?
          queue << child if child
        end
      end
    end
  end
end
