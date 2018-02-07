module Aha
  class ChunkArray(T)
    # 二维数组表示一维数组
    # 方便添加元素，不允许删除
    @values : Array(Array(T))
    @chunck_size : Int32 # 必须是2的n次
    @div_shift : Int32
    @size : Int32

    getter :size

    def capacity
      @values.size * @chunck_size
    end

    def initialize(initial_capacity, @chunck_size = 4096)
      raise "chunck_size should be power of 2" unless Aha.count_bit(@chunck_size.to_u32) == 1
      @div_shift = Aha.msb_for_2power(@chunck_size.to_u32)
      init_chunk_num = (initial_capacity + @chunck_size - 1) / chunck_size
      @values = Array(Array(T)).new(init_chunk_num) { |i| Array(T).new(initial_capacity: @chunck_size) }
      @size = 0
    end

    def <<(value : T)
      add value
    end

    def [](idx)
      @values[row idx][col idx]
    end

    def add(value : T)
      if size == capacity
        new_values = Array(Array(T)).new(initial_capacity: @values.size + 1)
        @values.each_with_index { |v, i| new_values[i] = v }
        new_values << Array(T).new(initial_capacity: @chunck_size)
        @values = new_values
      end
      @values[row(@size)] << value
      @size += 1
      return @size - 1
    end

    def clear
      @values.each { |va| va.clear }
      @size = 0
    end

    private def row(idx)
      idx >> @div_shift
    end

    private def col(idx)
      idx & (@chunck_size - 1)
    end
  end
end
