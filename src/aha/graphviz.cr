module Aha
  class Cedar
    def to_dot
      io = String::Builder.new
      to_dot(io)
      io.to_s
    end

    def to_dot(io)
      io.puts "digraph DFA {"
      io.puts "\tnode [color=lightblue2 style=filled]"
      (0...@array.size).each do |id|
        pid = at(@array, id).check
        next if pid < 0
        pbase = at(@array, pid).base
        label = pbase ^ id
        io.puts <<-DOT
        "node(#{pid})" -> "node(#{id})" [label="(#{label.to_s(16)})" color=black]
        DOT
        sib = at(@array, id).sibling
        sib_id = pbase ^ sib.to_i32
        if at(@array, sib_id).check == pid
          io.puts <<-DOT
          "node(#{id})" -> "node(#{sib_id})" [label="(#{sib.to_s(16)})" color=red]
          DOT
        end
      end
      io.puts "}"
    end
  end
end
