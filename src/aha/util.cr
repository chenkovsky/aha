module Aha
  ByteFormat = IO::ByteFormat::LittleEndian

  @[AlwaysInline]
  def self.pointer(arr : Array(T), idx) forall T
    arr.to_unsafe + idx
  end

  @[AlwaysInline]
  def self.pointer(arr : ArrayX(T), idx) forall T
    arr.ptr + idx
  end

  @[AlwaysInline]
  def self.pointer(arr : Pointer(T), idx) forall T
    arr + idx
  end

  macro at(arr, idx)
    (Aha.pointer({{arr}}, {{idx}}).value)
  end

  def self.count_bit(v : UInt32)
    v = v - ((v >> 1) & 0x55555555)
    v = (v & 0x33333333) + ((v >> 2) & 0x33333333)
    c = ((v + (v >> 4) & 0xF0F0F0F) * 0x1010101) >> 24
  end

  def self.is_power_of_two(v : UInt64)
    value != 0 && (value & (value - 1)) == 0
  end

  MultiplyDeBruijnBitPosition2 = [
    0, 1, 28, 2, 29, 14, 24, 3, 30, 22, 20, 15, 25, 17, 4, 8,
    31, 27, 13, 23, 21, 19, 16, 7, 26, 12, 18, 6, 11, 5, 10, 9,
  ]

  def self.msb_for_2power(v : UInt32)
    # 仅限于2的n次
    MultiplyDeBruijnBitPosition2[(v * 0x077CB531) >> 27]
  end

  def self.binary_search(arr, elem, reverse = false) : Int32
    # search in ordered array
    start = 0
    end_ = arr.size - 1
    while start <= end_
      mid = (start + end_) >> 1
      if arr[mid] == elem
        return mid
      elsif (arr[mid] > elem) && !reverse
        end_ = mid - 1
      else
        start = mid + 1
      end
    end
    return -(start + 1)
  end

  # 插入已经排过序的数组
  def self.ordered_insert(arr, target, first = 0, last = arr.size)
    # insert target into arr such that arr[first..last] is sorted,
    # given that arr[first..last-1] is already sorted.
    # Return the position where inserted.
    index = binary_search(arr, target)
    return index if index >= 0
    arr << target
    ((-index)...arr.size).reverse_each { |i| arr[i] = arr[i - 1] }
    place = -index - 1
    arr[place] = target
    return place
  end

  def self.bytes_cmp(b1 : Bytes, b2 : Bytes)
    len = b1.size
    len = b2.size if b2.size < b1.size
    (0...len).each do |i|
      cmp = b1[i] <=> b2[i]
      return cmp if cmp != 0
    end
    return 0 if b1.size == b2.size
    return 1 if b1.size > b2.size
    return -1
  end
end
