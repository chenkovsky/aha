require "levenshtein"

module Aha
  class BKTree(T)
    @dist_func : (T, T) -> Int32

    struct Node(T)
      @term : T
      @children : Hash(Int32, Node(T))
      getter :term, :children

      def initialize(@term, @children = {} of Int32 => Node(T))
      end
    end

    @nodes : Array(Node(T))

    def self.compile(keys : Array(String)) : BKTree(String)
      bk = BKTree(String).new do |s1, s2|
        Levenshtein.distance(s1, s2)
      end
      keys.each do |key|
        bk << key
      end
      return bk
    end

    def initialize(@nodes = [] of Node(T), &dist_func : (T, T) -> Int32)
      @dist_func = dist_func
    end

    def insert(key : T)
      if @nodes.empty?
        @nodes << Node(T).new(key)
      else
        cur_node = @nodes[0]
        while true
          score = @dist_func.call(cur_node.term, key)
          break if score == 0
          if child = cur_node.children[score]?
            cur_node = child
          else
            cur_node.children[score] = Node(T).new(key)
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
        yield cur.term, dist if dist <= threshold
        (-threshold..threshold).each do |d|
          child = cur.children[d + dist]?
          queue << child if child
        end
      end
    end
  end
end
