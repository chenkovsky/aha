require "./edit_distance"

module Aha
  class SymSpell
    # 对于每个字符串，前面的prefix_len长度的，进行max_edit_distance次delete操作后
    # 所有的子串的hash为key。
    # 查询的字符串的至多max_edit_distance编辑距离的字符串一定可以在hash表中找到。
    struct SuggestItem
      include Comparable(SuggestItem)
      @term : String
      @distance : Int32
      @val : Int32
      getter :term, :distance, :val

      def initialize(@term, @distance, @val)
      end

      def <=>(other : SuggestItem)
        @distance <=> other.distance
      end

      delegate :hash, to: @term
    end

    class SuggestionStage
      # 尽量将删除操作后，字符串相同的字符串放进同一个链表里面
      # An intentionally opacque class used to temporarily stage
      # dictionary data during the adding of many words. By staging the
      # data during the building of the dictionary data, significant savings
      # of time can be achieved, as well as a reduction in final memory usage.

      # 链表管理suggestion
      struct Node
        @suggestion : String
        @next : Int32
        getter :suggestion, :next

        def initialize(@suggestion, @next)
        end
      end

      struct Entry
        @count : Int32
        @first : Int32
        property :count, :first

        def initialize(@count, @first)
        end
      end

      @deletes : Hash(Int32, Entry)
      @nodes : ChunkArray(Node)

      def initialize(capacity : Int32 = 16384)
        @deletes = Hash(Int32, Entry).new(initial_capacity: capacity)
        @nodes = ChunkArray(Node).new(initial_capacity: capacity*2)
      end

      def delete_count
        @deletes.size
      end

      def node_count
        @nodes.size
      end

      def clear
        @deletes.clear
        @nodes.clear
      end

      # key 是删除
      def add(delete_hash : Int32, suggestion : String)
        entry = @deletes[delete_hash]?
        if entry.nil?
          entry = Entry.new(0, -1)
        end
        next_ = entry.first
        entry.count += 1
        entry.first = @nodes.size
        @deletes[delete_hash] = entry
        @nodes << Node.new(suggestion, next_)
      end

      def commit_to(permanet_deletes : Hash(Int32, Array(String)))
        @deletes.each do |key, entry|
          suggestions = permanet_deletes[key]?
          if suggestions.nil?
            suggestions = Array(String).new(entry.count)
          else
            suggestions_ = Array(String).new(entry.count + suggestions.size)
            suggestions.each { |s| suggestions_ << s }
            suggestions = suggestions_
          end
          next_ = entry.first
          while next_ >= 0
            node = @nodes[next_]
            suggestions << node.suggestion
            next_ = node.next
          end
          permanet_deletes[key] = suggestions
        end
      end
    end

    DefaultMaxEditDistance = 2
    DefaultPrefixLength    = 7
    DefaultCompactLevel    = 5

    @max_edit_distance : Int32
    # 前缀索引， 节省 90% 的内存
    # Longer prefix length means higher search speed at the cost of higher index size.
    @prefix_length : Int32
    @compact_mask : UInt32
    @max_length : Int32
    @deletes : Hash(Int32, Array(String))
    @words : Hash(String, Int32)

    def to_io(io : IO, format : IO::ByteFormat)
      @max_edit_distance.to_io io, format
      @prefix_length.to_io io, format
      @compact_mask.to_io io, format
      @max_length.to_io io, format

      # string pool
      string_to_id = {} of String => Int32
      @words.each { |key, val| string_to_id[key] ||= string_to_id.size }

      strings = Array(String).new(string_to_id.size, "")
      string_to_id.each { |k, id| strings[id] = k }
      Aha.string_array_to_io strings, io, format
      @words.size.to_io io, format
      @words.each { |k, _| string_to_id[k].to_io io, format }
      @words.each { |_, v| v.to_io io, format }

      @deletes.size.to_io io, format
      @deletes.each { |key, _| key.to_io io, format }
      @deletes.each { |_, val| val.size.to_io io, format }
      @deletes.each { |_, val| val.each { |s| string_to_id[s].to_io io, format } }
    end

    def self.from_io(io : IO, format : IO::ByteFormat) : self
      max_edit_distance = Int32.from_io io, format
      prefix_length = Int32.from_io io, format
      compact_mask = UInt32.from_io io, format
      max_length = Int32.from_io io, format
      strings : Array(String) = Aha.string_array_from_io io, format
      STDERR.puts "line 150"
      strings.each { |x| STDERR.puts "str:#{x.inspect}" }
      word_num = Int32.from_io io, format
      STDERR.puts "word_num:#{word_num}"
      words = Hash.zip((0...word_num).map { |_| strings[Int32.from_io(io, format)] }, (0...word_num).map { |_| Int32.from_io(io, format) })
      delete_num = Int32.from_io io, format
      keys = (0...delete_num).map { |_| Int32.from_io io, format }
      val_sizes = (0...delete_num).map { |_| Int32.from_io io, format }
      vals = (0...delete_num).map { |i| (0...val_sizes[i]).map { |_| strings[Int32.from_io(io, format)] } }
      deletes = Hash(Int32, Array(String)).zip(keys, vals)

      return SymSpell.new(max_edit_distance, prefix_length, compact_mask, max_length, deletes, words)
    end

    getter :max_edit_distance, :prefix_length, :max_length
    delegate :size, to: @words

    def entry_count
      @deletes.size
    end

    def add(key : String, val : Int32)
      create_dictionary_entry key, val
    end

    def self.compile(keys : Hash(String, Int32),
                     max_edit_distance = DefaultMaxEditDistance,
                     prefix_length = DefaultPrefixLength,
                     compact_level = DefaultCompactLevel)
      spell = SymSpell.new(max_edit_distance, prefix_length, compact_level)
      staging = SuggestionStage.new
      keys.each do |key, val|
        spell.create_dictionary_entry(key, val, staging)
      end
      spell.commit_staged(staging)
      return spell
    end

    def self.compile(keys : Array(String),
                     max_edit_distance = DefaultMaxEditDistance,
                     prefix_length = DefaultPrefixLength,
                     compact_level = DefaultCompactLevel)
      spell = SymSpell.new(max_edit_distance, prefix_length, compact_level)
      staging = SuggestionStage.new
      keys.each_with_index do |key, idx|
        spell.create_dictionary_entry(key, idx, staging)
      end
      spell.commit_staged(staging)
      return spell
    end

    def save(path)
      File.open(path, "wb") do |f|
        to_io f, IO::ByteFormat::LittleEndian
      end
    end

    def self.load(path)
      File.open(path, "rb") do |f|
        return SymSpell.from_io f, IO::ByteFormat::LittleEndian
      end
    end

    protected def initialize(@max_edit_distance, @prefix_length, @compact_mask, @max_length, @deletes, @words)
    end

    def initialize(@max_edit_distance = DefaultMaxEditDistance,
                   @prefix_length = DefaultPrefixLength,
                   compact_level = DefaultCompactLevel)
      @max_length = 0
      raise "max_edit_distance <0 " if max_edit_distance < 0
      raise "prefix_length < 1 || prefix_length <= max_edit_distance" if prefix_length < 1 || prefix_length <= max_edit_distance
      raise "compact_level > 16" if compact_level > 16
      @words = {} of String => Int32
      @deletes = {} of Int32 => Array(String)
      @compact_mask = (UInt32::MAX >> (3 + compact_level)) << 2
    end

    def create_dictionary_entry(key : String, val : Int32, staging : SuggestionStage? = nil) : Bool
      if @words.has_key? key
        @words[key] = val
        return false
      end
      @words[key] = val
      @max_length = key.size if key.size > @max_length
      edits = edits_prefix key
      # 如果有缓冲区，那么先加入缓冲区，否则直接加入
      unless staging.nil?
        edits.each do |delete|
          staging.add string_hash(delete), key
        end
      else
        edits.each do |delete|
          delete_hash = string_hash delete
          suggestions = @deletes[delete_hash]?
          if suggestions.nil?
            suggestions = Array(String).new(1)
          end
          suggestions << key
          @deletes[delete_hash] = suggestions
        end
      end
      return true
    end

    def commit_staged(staging : SuggestionStage)
      staging.commit_to @deletes
    end

    # return suggestion items
    # 如果all为false，那么只返回编辑距离最短的
    def match(input : String, max_edit_distance : Int32 = 0, all : Bool = true) : Array(SuggestItem)
      raise "max_edit_distance > @max_edit_distance" if max_edit_distance > @max_edit_distance
      input_len = input.size
      suggestions = Array(SuggestItem).new
      if input_len - max_edit_distance > max_length
        return suggestions
      end
      # deletes we've considered already
      set1 = Set(String).new
      # suggestions we've considered already
      set2 = Set(String).new

      val = @words[input]?
      if !val.nil?
        suggestions << SuggestItem.new(input, 0, val)
        # 如果存在距离0，且只要返回最近的，那么立刻返回
        return suggestions unless all
      end
      set2 << input
      max_edit_distance2 = max_edit_distance
      candidate_pointer = 0
      candidates = Array(String).new
      input_prefix_len = input_len
      # 因为我们只对prefix_length的长度做了预先计算，所以我们也需要得到input的prefix_length的子串
      if input_prefix_len > prefix_length
        input_prefix_len = prefix_length
        candidates << input[0, input_prefix_len]
      else
        candidates << input
      end
      distance_comparer = EditDistance::DamerauLevenshtein.new
      while candidate_pointer < candidates.size
        candidate = candidates[candidate_pointer]
        candidate_pointer += 1
        candidate_len = candidate.size
        length_diff = input_prefix_len - candidate_len
        if length_diff > max_edit_distance2
          # if canddate distance is already higher than suggestion distance,
          # than there are no better suggestions to be expected
          next if all
          break
        end
        dict_suggestions = @deletes[string_hash(candidate)]?
        if dict_suggestions
          # iterate through suggestions (to other correct dictionary items)
          # of delete item and add them to suggestion list
          dict_suggestions.each do |suggestion|
            suggestion_len = suggestion.size
            next if suggestion == input
            # 如果suggestion和input长度相差超过最大编辑距离,那么肯定不合法
            # candidate_len > suggestion_len,肯定是hash碰撞了
            # suggestion_len == candidate_len && suggestion != candidate也是
            if (suggestion_len - input_len).abs > max_edit_distance2 || \
                  suggestion_len < candidate_len || \
                  (suggestion_len == candidate_len && suggestion != candidate)
              next
            end
            sugg_prefix_len = [suggestion_len, prefix_length].min
            if sugg_prefix_len > input_prefix_len && (sugg_prefix_len - candidate_len) > max_edit_distance2
              # 编辑距离肯定 > max_edit_distance2
              next
            end
            # True Damerau-Levenshtein Edit Distance: adjust distance, if both distances>0
            # We allow simultaneous edits (deletes) of maxEditDistance on on both the dictionary and the input term.
            # For replaces and adjacent transposes the resulting edit distance stays <= maxEditDistance.
            # For inserts and deletes the resulting edit distance might exceed maxEditDistance.
            # To prevent suggestions of a higher edit distance, we need to calculate the resulting edit distance, if there are simultaneous edits on both sides.
            # Example: (bank==bnak and bank==bink, but bank!=kanb and bank!=xban and bank!=baxn for maxEditDistance=1)
            # Two deletes on each side of a pair makes them all equal, but the first two pairs have edit distance=1, the others edit distance=2.
            distance = 0
            min = 0
            if candidate_len == 0
              # suggestions which have no common chars with input (inputLen<=maxEditDistance && suggestionLen<=maxEditDistance)
              distance = [input_len, suggestion_len].max
              next if distance > max_edit_distance2
              if set2.includes?(suggestion)
                next
              else
                set2 << suggestion
              end
            elsif suggestion_len == 1
              if input.index(suggestion[0]).nil?
                distance = input_len
              else
                distance = input_len - 1
              end
              next if distance > max_edit_distance2
              if set2.includes? suggestion
                next
              else
                set2 << suggestion
              end
            else
              # number of edits in prefix ==maxediddistance  AND no identic suffix
              # , then editdistance>maxEditDistance and no need for Levenshtein calculation
              # (inputLen >= prefixLength) && (suggestionLen >= prefixLength)
              min = [input_len, suggestion_len].min
              if (prefix_length - max_edit_distance == candidate_len) &&
                 (((min > 1) &&
                 (input[input_len + 1 - min, input.size] != suggestion[suggestion_len + 1 - min, suggestion.size])) ||
                 ((min > 0) && (input[input_len - min] != suggestion[suggestion_len - min]) &&
                 ((input[input_len - min - 1] != suggestion[suggestion_len - min]) ||
                 (input[input_len - min] != suggestion[suggestion_len - min - 1]))))
                next
              else
                next if (!all && !delete_in_suggestion_prefix(candidate, candidate_len, suggestion, suggestion_len))
                next if set2.includes? suggestion
                set2 << suggestion
                distance = distance_comparer.distance(input, suggestion, max_edit_distance2)
                next if distance < 0
              end
            end
            if distance <= max_edit_distance2
              suggestion_val = @words[suggestion]
              si = SuggestItem.new(suggestion, distance, suggestion_val)
              if all
                suggestions << si
              else
                # 只留最近的
                if distance < max_edit_distance2
                  suggestions.clear
                  suggestions << si
                elsif distance == max_edit_distance2
                  suggestions << si
                end
                max_edit_distance2 = distance
              end
            end
          end
        end
        if length_diff < max_edit_distance && candidate_len <= prefix_length
          next if !all && length_diff >= max_edit_distance2
          # 继续寻找更短的
          (0...candidate_len).each do |i|
            delete = candidate[0, i] + candidate[i + 1, candidate_len]
            unless set1.includes? delete
              set1 << delete
              candidates << delete
            end
          end
        end
      end
      suggestions.sort if suggestions.size > 1
      return suggestions
    end

    private def sort_by_val(suggestions : Array(SuggestItem))
      suggestions.sort! do |s1, s2|
        cmp = s1 <=> s2
        cmp = s2.val <=> s1.val if cmp == 0
        cmp
      end
    end

    # 此时假设terms的val是频率
    def match(terms : Array(String), max_edit_distance : Int32 = @max_edit_distance, all : Bool = true) : Array(SuggestItem)
      raise "max_edit_distance > @max_edit_distance" if max_edit_distance > @max_edit_distance
      input = terms.join(" ")
      suggestions = [] of SuggestItem      # suggestions for a single term
      suggestion_parts = [] of SuggestItem # 1 line with separate parts
      last_combi = false
      # translate every term to its best suggestion, otherwise it remains unchanged
      terms.each_with_index do |term, i|
        suggestions_previous_term = suggestions.map { |s| s }
        suggestions = match(term, max_edit_distance, false)
        sort_by_val(suggestions)
        if (i > 0 && !last_combi)
          # 上一个单词没有被合并过的话，那么尝试与当前单词合并
          suggestions_combi = match(terms[i - 1] + term, max_edit_distance, false)
          sort_by_val(suggestions_combi)
          unless suggestions_combi.empty?
            # 组合后在编辑距离内有合适的单词
            best1 = suggestion_parts[-1]
            if suggestions.size > 0
              # 当前单个词在编辑距离内有词在词库中
              best2 = suggestions[0]
            else
              # 当前单个词不在词库里面
              best2 = SuggestItem.new(term, max_edit_distance + 1, 0)
            end
            input_ = terms[i - 1] + " " + term
            suggest_ = best1.term + " " + best2.term
            distance_comparer = EditDistance::DamerauLevenshtein.new
            distance1 = distance_comparer.distance(input_, suggest_, max_edit_distance)
            if distance1 >= 0 && suggestions_combi[0].distance + 1 < distance1
              # 合并后的编辑距离比每个单独的编辑距离小，那么合并
              suggestions_combi[0] = SuggestItem.new(suggestions_combi[0].term, suggestions_combi[0].distance + 1, suggestions_combi[0].val)
              suggestion_parts[-1] = suggestions_combi[0]
              last_combi = true
              next
            end
          end
        end
        last_combi = false
        # alway split terms without suggestion / never split terms with suggestion ed=0 / never split single char terms
        if suggestions.size > 0 && (suggestions[0].distance == 0 || term.size == 1)
          # choose best suggestion
          suggestion_parts << suggestions[0]
        else
          # if no perfect suggestion, split word into pairs
          suggestions_split = [] of SuggestItem
          # add original term
          suggestions_split << suggestions[0] if suggestions.size > 0
          if term.size > 1
            (1...term.size).each do |j|
              part1 = term[0, j]
              part2 = term[j, term.size]
              suggestions1 = match(part1, max_edit_distance, false)
              sort_by_val(suggestions1)
              if suggestions1.size > 0
                # 分开来补全和不分开补全出了相同的东西
                break if suggestions.size > 0 && suggestions[0].term == suggestions1[0].term
                suggestions2 = match(part2, max_edit_distance, false)
                sort_by_val(suggestions2)
                if suggestions2.size > 0
                  # 分开来补全和不分开补全出了相同的东西
                  break if suggestions.size > 0 && suggestions[0].term == suggestions2[0].term
                  # 切分出来的term
                  split_term = suggestions1[0].term + " " + suggestions2[0].term

                  distance_comparer2 = EditDistance::DamerauLevenshtein.new
                  distance2 = distance_comparer2.distance(split_term, term, max_edit_distance)
                  distance2 = max_edit_distance + 1 if distance2 < 0
                  suggestion_split = SuggestItem.new(split_term, distance2, [suggestions1[0].val, suggestions2[0].val].min)
                  suggestions_split << suggestion_split
                  break if suggestion_split.distance == 1
                end
              end
            end
            if suggestions_split.size > 0
              suggestions_split.sort { |x, y| 2 * (x.distance <=> y.distance) - (x.val <=> y.val) }
              suggestion_parts << suggestions_split[0]
            else
              si = SuggestItem.new(term, max_edit_distance + 1, 0)
              suggestion_parts << si
            end
          else
            si = SuggestItem.new(term, max_edit_distance + 1, 0)
            suggestion_parts << si
          end
        end
      end
      count = Int32::MAX
      s = String.build do |sb|
        suggestion_parts.each_with_index do |si, i|
          sb << si.term
          sb << ' ' if i != suggestion_parts.size - 1
          count = si.val if si.val < count
        end
      end
      distance_comparer3 = EditDistance::DamerauLevenshtein.new
      suggestion = SuggestItem.new(s, distance_comparer3.distance(input, s, Int32::MAX), count)
      return [suggestion]
    end

    # check whether all delete chars are present in the suggestion prefix in correct order,
    # otherwise this is just a hash collision
    private def delete_in_suggestion_prefix(delete : String,
                                            delete_len : Int32,
                                            suggestion : String,
                                            suggestion_len : Int32)
      return true if delete_len == 0
      suggestion_len = @prefix_length if @prefix_length < suggestion_len
      j = 0
      (0...delete_len).each do |i|
        del_char = delete[i]
        while j < suggestion_len && del_char != suggestion[j]
          j += 1
        end
        return false if j == suggestion_len
      end
      return true
    end

    # 删除至多max_edit_distance个字符，得到字符串集合
    private def edits(word : String, edit_distance : Int32, delete_words : Set(String))
      edit_distance += 1
      if word.size > 1
        (0...word.size).each do |i|
          delete = word[0, i] + word[i + 1, word.size]
          unless delete_words.includes? delete
            delete_words << delete
            edits(delete, edit_distance, delete_words) if edit_distance < @max_edit_distance
          end
        end
      end
      return delete_words
    end

    private def edits_prefix(key : String)
      set = Set(String).new
      set << "" if key.size <= @max_edit_distance
      key = key[0, @prefix_length] if key.size > @prefix_length
      set << key
      edits(key, 0, set)
    end

    private def string_hash(s : String) : Int32
      len = s.size
      len_mask = len
      len_mask = 3 if len_mask > 3
      hash = 2166136261
      (0...len).each do |i|
        hash ^= s[i].ord
        hash *= 16777619
      end
      hash &= @compact_mask
      hash |= len_mask
      return hash.to_i32
    end
  end
end
