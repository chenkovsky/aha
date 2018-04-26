module Aha
  class CedarX(T)
    def to_dot
      io = String::Builder.new
      to_dot(io)
      io.to_s
    end

    def to_dot(io)
      io.puts "digraph DFA {"
      io.puts "\tnode [color=lightblue2 style=filled]"
      (0...@size).each do |id|
        pid = Aha.at(@array, id).check
        next if pid < 0
        pbase = Aha.at(@array, pid).base
        label = pbase ^ id
        io.puts <<-DOT
        "node(#{pid})" -> "node(#{id})" [label="(#{label.to_s(16)})" color=black]
        DOT
        sib = Aha.at(@array, id).sibling
        sib_id = pbase ^ sib.to_i32
        if Aha.at(@array, sib_id).check == pid
          io.puts <<-DOT
          "node(#{id})" -> "node(#{sib_id})" [label="(#{sib.to_s(16)})" color=red]
          DOT
        end
      end
      io.puts "}"
    end
  end

  class SAM
    def to_dot
      io = String::Builder.new
      to_dot(io)
      io.to_s
    end

    def to_dot(io)
      io.puts "digraph DFA {"
      io.puts "\tnode [color=lightblue2 style=filled]"
      @slinks.each_with_index do |slink, idx|
        io.puts "\"node(#{idx})\" [label=\"#{idx}:#{@lens[idx]}\"]"
        @nexts[idx].each do |k, v|
          io.puts <<-DOT
            "node(#{idx})" -> "node(#{v})" [label="(#{k})"]
          DOT
        end
        if slink >= 0
          io.puts <<-DOT
            "node(#{idx})" -> "node(#{slink})" [style=dashed]
          DOT
        end
      end
      io.puts "}"
    end
  end
end
