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

  macro array_to_io(arr, type_, io, format)
    {{arr}}.size.to_io {{io}}, {{format}}
    (0...{{arr}}.size).each { |idx| Aha.to_io Aha.at({{arr}}, idx), {{type_}}, {{io}}, {{format}} }
    {% if type_.id == "UInt8" %}
      %padding = 4 - ({{arr}}.size % 4)
      if %padding != 4
        (0...%padding).each{|_| Aha.to_io 0_u8, UInt8, io, format}
      end
    {% end %}
  end

  macro array_from_io(type_, io, format)
    begin
      %size = Aha.from_io Int32, {{io}}, {{format}}
      %ret = Array({{type_}}).new(%size){|_| Aha.from_io {{type_}}, {{io}}, {{format}} }
      {% if type_.id == "UInt8" %}
        %padding = 4 - (%size % 4)
        if %padding != 4
          (0...%padding).each{|_| Aha.from_io UInt8, io, format}
        end
      {% end %}
      %ret
    end
  end

  macro ptr_to_io(arr, size, type_, io, format)
    ({{size}}).to_i64.to_io {{io}}, {{format}}
    (0...{{size}}).each { |idx| Aha.to_io Aha.at({{arr}}, idx), {{type_}}, {{io}}, {{format}} }
    {% if type_.id == "UInt8" %}
      %padding = 4 - ({{size}} % 4)
      if %padding != 4
        (0...%padding).each{|_| Aha.to_io 0_u8, UInt8, io, format}
      end
    {% end %}
  end

  macro ptr_from_io(type_, io, format, cap_func)
    begin
      %size = Aha.from_io Int64, {{io}}, {{format}}
      %capacity = {{cap_func}}(%size)
      %ret = Pointer({{type_}}).malloc(%capacity)
      (0...%size).each {|i| %ret[i] = Aha.from_io {{type_}}, {{io}}, {{format}} }
      {% if type_.id == "UInt8" %}
        %padding = 4 - (%size % 4)
        if %padding != 4
          (0...%padding).each{|_| Aha.from_io UInt8, io, format}
        end
      {% end %}
      { %ret, %size, %capacity}
    end
  end

  macro to_io(val, type_, io, format)
    {% if type_.id == "Char" %}
      ({{val}}).ord.to_io {{io}}, {{format}}
    {% else %}
      ({{val}}).to_io {{io}}, {{format}}
    {% end %}
  end

  macro from_io(type_, io, format)
    {% if type_.id == "Char" %}
      (Char::ZERO + Int32.from_io({{io}}, {{format}}))
    {% else %}
      ({{type_}}.from_io {{io}}, {{format}})
    {% end %}
  end

  macro hash_to_io(hash, ktype_, vtype_, io, format)
    {{hash}}.size.to_io {{io}}, {{format}}
    {{hash}}.each do|k, v|
      Aha.to_io k, {{ktype_}}, {{io}}, {{format}}
      Aha.to_io v, {{vtype_}}, {{io}}, {{format}}
    end
  end

  macro hash_from_io(ktype_, vtype_, io, format)
    begin
      %size = Int32.from_io {{io}}, {{format}}
      %hash = Hash({{ktype_}},{{vtype_}}).new(initial_capacity: %size)
      (0...%size).each do |i|
        k = Aha.from_io {{ktype_}}, {{io}}, {{format}}
        v = Aha.from_io {{vtype_}}, {{io}}, {{format}}
        %hash[k] = v
      end
      %hash
    end
  end

  macro string_array_to_io(string_arr, io, format)
    {{string_arr}}.size.to_io {{io}}, {{format}}
    %total_length = 0
    {{string_arr}}.each do |s|
      %total_length += s.bytesize + 1
      io.print s
      io.write_byte 0_u8
    end
    %padding = 4 - %total_length % 4
    if %padding != 4
      (0...%padding).each{|_| Aha.to_io 0_u8, UInt8, io, format}
    end
  end

  macro string_array_from_io(io, format)
    begin
      %size = Int32.from_io {{io}}, {{format}}
      %total_length = 0
      %bytes = Array(UInt8).new
      %arr = (0...%size).map do|_|
        s = Aha.read_utf8_string({{io}}, %bytes)
        %total_length += %bytes.size + 1
        s
      end
      %padding = 4 - %total_length % 4
      if %padding != 4
        (0...%padding).each{|_| Aha.from_io UInt8, {{io}}, {{format}} }
      end
      %arr
    end
  end

  def self.read_utf8_string(io, bytes = Array(UInt8).new)
    bytes.clear
    s = io.read_utf8_byte.not_nil!
    while s != 0
      bytes << s
      s = io.read_utf8_byte.not_nil!
    end
    return String.new(bytes.to_unsafe, bytes.size)
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

  protected def self.byte_index_to_char_index(seq : String)
    start_byte_idx = 0
    ret = {} of Int32 => Int32
    seq.each_char_with_index do |chr, idx|
      ret[start_byte_idx] = idx
      start_byte_idx += chr.bytesize
    end
    ret[start_byte_idx] = seq.size
    return ret
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
