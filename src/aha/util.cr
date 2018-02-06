module Aha
  macro pointer(arr, idx)
    ({{arr}}.to_unsafe + ({{idx}}))
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

  macro to_io(val, type_, io, format)
    {% if type_.id == "Char" %}
      {{val}}.ord.to_io {{io}}, {{format}}
    {% else %}
      {{val}}.to_io {{io}}, {{format}}
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

  MultiplyDeBruijnBitPosition2 = [
    0, 1, 28, 2, 29, 14, 24, 3, 30, 22, 20, 15, 25, 17, 4, 8,
    31, 27, 13, 23, 21, 19, 16, 7, 26, 12, 18, 6, 11, 5, 10, 9,
  ]

  def self.msb_for_2power(v : UInt32)
    # 仅限于2的n次
    MultiplyDeBruijnBitPosition2[(v * 0x077CB531) >> 27]
  end
end
