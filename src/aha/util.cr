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
end
