module Aha
  macro pointer(arr, idx)
    ({{arr}}.to_unsafe + ({{idx}}))
  end

  macro at(arr, idx)
    (Aha.pointer({{arr}}, {{idx}}).value)
  end

  macro array_to_io(arr, io, format)
    {{arr}}.size.to_io {{io}}, {{format}}
    (0...{{arr}}.size).each { |idx| Aha.at({{arr}}, idx).to_io {{io}}, {{format}} }
  end

  macro array_from_io(arr, type_, io, format)
    size = Int32.from_io {{io}}, {{format}}
    {{arr}} = Array({{type_}}).new(size){|_| {{type_}}.from_io {{io}}, {{format}} }
  end
end
