import Base: rpad as brpad

rx = r"\s*\S+\s*"

"""
    words(text)

Get individual words in a string, their position and size.
"""
words(text) = map(
    m -> (m.offset, m.offset + textlen(m.match), m.match, textlen(m.match)),
    eachmatch(rx, text),
)

"""
    characters(word)

Get individual characters in a word, their position and size.
"""
function characters(word)
    chars = collect(word)
    widths = textwidth.(chars)
    return map(i -> (chars[i], widths[i]), 1:length(chars))
end

"""
    style_at_each_line(text)

Get style tags over multiple lines and repeat them at the start/end
of each line.
"""
function style_at_each_line(text)
    lines = split(text, "\n")
    for (i, line) in enumerate(lines)
        for tag in eachmatch(OPEN_TAG_REGEX, line)
            markup = tag.match[2:(end - 1)]
            isclosed = occursin("{/" * markup * "}", line)

            if !isclosed && i < length(lines)
                lines[i + 1] = "{$markup}" * lines[i + 1]
            end
        end
    end
    # return join(lines, "\e[0m\n")
    return join(lines, "\n")
end

"""
    split_tags_into_words(text)

Split markup tags with multiple words 
into multiple tags with a single word each.
"""
function split_tags_into_words(text)
    tags = map(m -> m.match[2:(end - 1)], eachmatch(OPEN_TAG_REGEX, text))

    for markup in tags
        tag = match(Regex("\\{$markup\\}"), text)
        isnothing(tag) && continue

        close_rx = r"(?<!\{)\{(?!\{)\/" * markup * r"\}"
        close_tag = match(close_rx, text)

        isnothing(close_tag) && continue

        tag_words = map(
            w -> replace(replace(w, "{" => ""), "}" => ""),
            ([w[3] for w in words(tag.match)]),
        )
        if length(tag_words) > 1
            openers = join(map(w -> "{" * rstrip(w) * "}", tag_words))
            closers = join(map(w -> "{/" * rstrip(w) * "}", tag_words))

            try
                text =
                    text[1:(tag.offset - 1)] *
                    openers *
                    text[(tag.offset + textwidth(markup) + 2):(close_tag.offset - 1)] *
                    closers *
                    text[(close_tag.offset + textwidth(markup) + 3):end]
            catch
                text =
                    text[1:prevind(text, tag.offset - 1)] *
                    openers *
                    text[nextind(text, tag.offset + textwidth(markup) + 2):prevind(
                        text,
                        close_tag.offset - 1,
                    )] *
                    closers *
                    text[prevind(text, close_tag.offset + textwidth(markup) + 3):end]
            end
        end
    end
    return text
end

"""
    reshape_text(text::AbstractString, width::Int)

Reshape a text to have a given width. 

Insert newline characters in a string so that each line is within the given width.
"""
function reshape_text(text::AbstractString, width::Int)
    occursin('\n', text) && (return do_by_line(ln -> reshape_text(ln, width), text))

    textlen(text) ≤ width && return text
    text = split_tags_into_words(text)
    position = 0
    cuts = []
    for (start, _, word, word_length) in words(text)
        if position + word_length > width
            len_t = length(text[1:start])
            # we need to cut the text
            if word_length > width
                # the word is longer than the line
                word_chars = characters(word)
                position > 0 && push!(cuts, len_t + length(cuts))
                _, position = first(word_chars)  # width of first char

                for (i, (char, w)) in enumerate(word_chars[2:end])
                    if position + w > width
                        push!(cuts, len_t + length(cuts) + i)
                        position = w
                    else
                        position += w
                    end
                end

            elseif position > 0 && start > 1
                push!(cuts, len_t + length(cuts))
                position = word_length
            end
        else
            position += word_length
        end
    end

    chars = collect(text)
    for cut in cuts
        insert!(chars, cut, '\n')
    end

    apply_style(style_at_each_line(String(chars)))
end

"""
    justify(text::AbstractString, width::Int)::String

Justify a piece of text spreading out text to fill in a given width.
"""
function justify(text::AbstractString, width::Int)::String
    returnfn(text) = text * ' '^(width - textlen(text))

    occursin('\n', text) && (return do_by_line(ln -> justify(ln, width), text))

    # cleanup text
    text = strip(text)
    text = endswith(text, "\e[0m") ? text[1:(end - 4)] : text
    text = strip(text)
    n_spaces = width - textlen(text)
    (n_spaces < 2 || textlen(text) ≤ 0.5width) && (return returnfn(text))

    # get number of ' ' and their location in the string
    spaces_locs = map(m -> m[1], findall(" ", text))
    spaces_locs = length(spaces_locs) < 2 ? spaces_locs : spaces_locs[1:(end - 1)]
    n_locs = length(spaces_locs)
    n_locs < 1 && (return returnfn(text))
    space_per_loc = div(n_spaces, n_locs)
    space_per_loc == 0 && (return returnfn(text))

    inserted = 0
    for (last, loc) in loop_last(spaces_locs)
        n_to_insert = last ? width - textlen(text) : space_per_loc
        to_insert = " "^n_to_insert
        text = replace_text(text, loc + inserted, loc + inserted, to_insert)
        inserted += n_to_insert
    end
    return returnfn(text)
end

"""
    text_to_width(text::AbstractString, width::Int)::String

Cast a text to have a given width by reshaping, it and padding.
It includes an option to justify the text (:left, :right, :center, :justify).
"""
function text_to_width(
    text::AbstractString,
    width::Int,
    justify::Symbol;
    background = nothing,
)::String
    # reshape text
    if Measure(text).w > width
        text = reshape_text(text, width - 1)
    end
    return pad(text, width, justify)
end
