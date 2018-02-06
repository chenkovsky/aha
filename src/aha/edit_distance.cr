module Aha
  class SymSpell
    module EditDistance
      struct DamerauLevenshtein
        @v0 : Array(Int32) # v0, v2 其实是计算中的临时空间，这么写是为了避免申请释放带来的开销
        @v2 : Array(Int32)

        def initialize
          @v0 = [] of Int32
          @v2 = [] of Int32
        end

        def distance(base : String, string2 : String, max_distance : Int32)
          return string2.size if base.size == 0
          return base.size if string2.size == 0
          if base.size > string2.size
            string1, string2 = string2, base
          else
            string1 = base
          end
          slen = string1.size
          tlen = string2.size
          # ignore common suffix
          while slen > 0 && string1[slen - 1] == string2[tlen - 1]
            slen -= 1
            tlen -= 1
          end
          # ignore common prefix
          start = 0
          if string1[0] == string2[0] || slen == 0
            while start < slen && string1[start] == string2[start]
              start += 1
            end
            slen -= start
            tlen -= start
            # if all of shorter string matches prefix and/or suffix of longer string, then
            # edit distance is just the delete of additional characters present in longer string
            return tlen if slen == 0
            string2 = string2[start, tlen] # faster than string2[start+j] in inner loop below
          end
          len_diff = tlen - slen
          if max_distance < 0 || max_distance > tlen
            max_distance = tlen
          elsif len_diff > max_distance
            return -1
          end
          if tlen > @v0.size
            @v0 = Array(Int32).new(tlen, 0)
            @v2 = Array(Int32).new(tlen, 0)
          else
            (0...tlen).each { |i| @v2[i] = 0 }
          end
          (0...tlen).each do |j|
            @v0[j] = j < max_distance ? (j + 1) : (max_distance + 1)
          end
          j_start_offset = max_distance - (tlen - slen)
          have_max = max_distance < tlen
          j_start = 0
          j_end = max_distance
          schar = string1[0]
          current = 0
          (0...slen).each do |i|
            prev_schar = schar
            schar = string1[start + i]
            tchar = string2[0]
            left = i
            current = left + 1
            next_trans_cost = 0
            # no need to look beyond window of lower right diagonal -
            # maxDistance cells (lower right diag is i - lenDiff)
            # and the upper left diagonal + maxDistance cells (upper left is i)
            j_start += (i > j_start_offset) ? 1 : 0
            j_end += (j_end < tlen) ? 1 : 0
            (j_start...j_end).each do |j|
              above = current
              this_trans_cost = next_trans_cost
              next_trans_cost = @v2[j]
              @v2[j] = current = left # cost of diagonal (substitution)
              left = @v0[j]           # left now equals current cost (which will be diagonal at next iteration)
              prev_tchar = tchar
              tchar = string2[j]
              if schar != tchar
                current = left if left < current   # insertion
                current = above if above < current # deletion
                current += 1
                if i != 0 && j != 0 && schar == prev_tchar && prev_schar == tchar
                  this_trans_cost += 1
                  current = this_trans_cost if this_trans_cost < current # transposition
                end
              end
              @v0[j] = current
            end
            return -1 if have_max && @v0[i + len_diff] > max_distance
          end
          return (current <= max_distance) ? current : -1
        end
      end
    end
  end
end
