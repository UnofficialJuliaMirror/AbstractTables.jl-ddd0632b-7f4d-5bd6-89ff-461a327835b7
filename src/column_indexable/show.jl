# Adapted from
# https://github.com/JuliaData/AbstractTables.jl/blob/e5afc569504ecf08ec769fd52a78da4027eab35f/src/AbstractTable/show.jl

# function Base.summary(tbl::AbstractTable) # -> String
#     nrows, ncols = nrow(tbl), ncol(tbl)
#     return @sprintf("%d×%d %s", nrows, ncols, typeof(tbl))
# end

let
    local io = IOBuffer(Array(UInt8, 80), true, true)
    global ourstrwidth
    function ourstrwidth(x::Any) # -> Int
        truncate(io, 0)
        ourshowcompact(io, x)
        return position(io)
    end
    ourstrwidth(x::AbstractString) = strwidth(x) + 2 # -> Int
    myconv = VERSION < v"0.4-" ? convert : Base.unsafe_convert
    ourstrwidth(s::Symbol) =
        @compat Int(ccall(:u8_strwidth,
                          Csize_t,
                          (Ptr{UInt8}, ),
                          myconv(Ptr{UInt8}, s)))
end

ourshowcompact(io::IO, x::Any) = showcompact(io, x) # -> Void
ourshowcompact(io::IO, x::AbstractString) = showcompact(io, x) # -> Void
ourshowcompact(io::IO, x::Symbol) = print(io, x) # -> Void

function getmaxwidths(tbl::AbstractTable, rowlabel, limit, offset)
    ncols = ncol(tbl)
    widths = [ Vector{Int}() for j in 1:ncols ]
    maxwidths = Array{Int}(ncol(tbl) + 1)
    undefstrwidth = ourstrwidth(Base.undef_ref_str)

    rows = eachrow(tbl)
    st = start(rows)
    i = 1
    while (i <= offset) & (!done(rows, st))
        row, st = next(rows, st)
        i += 1
    end
    while (i <= offset + limit) & (!done(rows, st))
        row, st = next(rows, st)
        for (j, v) in enumerate(row)
            try
                push!(widths[j], ourstrwidth(v))
            catch
                push!(widths[j], undefstrwidth)
            end
        end
        i += 1
    end
    flds = fields(tbl)
    for j in 1:ncols
        if isempty(widths[j])
            maxwidths[j] = ourstrwidth(flds[j])
        else
            maxwidths[j] = max(maximum(widths[j]), ourstrwidth(flds[j]))
        end
    end
    maxwidths[end] = max(ourstrwidth(rowlabel), ndigits(limit)+1)
    return maxwidths
end

function getprintedwidth(maxwidths::Vector{Int}) # -> Int
    # Include length of line-initial |
    totalwidth = 1
    for i in 1:length(maxwidths)
        # Include length of field + 2 spaces + trailing |
        totalwidth += maxwidths[i] + 3
    end
    return totalwidth
end

function pad(io, padding)
    for _ in 1:padding
        print(io, ' ')
    end
end

function print_bounding_line(io, maxwidths, rightmost)
    rowmaxwidth = maxwidths[end]
    write(io, '├')
    for itr in 1:(rowmaxwidth + 2)
        write(io, '─')
    end
    write(io, '┼')
    for j in 1:rightmost
        for itr in 1:(maxwidths[j] + 2)
            write(io, '─')
        end
        if j < rightmost
            write(io, '┼')
        else
            write(io, '┤')
        end
    end
    write(io, '\n')
end

function show_tbl_rows(io::IO, tbl, maxwidths, rightmost, rowlabel, limit, offset)
    rowmaxwidth = maxwidths[end]
    flds = fields(tbl)
    rows = eachrow(tbl, flds[1:rightmost]...)
    st = start(rows)
    i = 1
    while (i <= offset) & (!done(rows, st))
        row, st = next(rows, st)
        i += 1
    end
    while (i <= offset + limit) & (!done(rows, st))
        row, st = next(rows, st)
        @printf(io, "│ %d", i)
        pad(io, rowmaxwidth - ndigits(i))
        print(io, " │ ")
        # print table entry
        for j in 1:rightmost
            v = row[j]
            strlen = ourstrwidth(v)
            ourshowcompact(io, v)
            pad(io, maxwidths[j] - strlen)
            if j == rightmost
                if i == (limit+offset)
                    print(io, " │")
                else
                    print(io, " │\n")
                end
            else
                print(io, " │ ")
            end
        end
        i += 1
    end
    if (i > (limit+offset)) & (!done(rows, st))
        print_row_footer(io, tbl, tblrowdim(tbl), limit, offset)
    end
    return
end

function print_row_footer(io, tbl::AbstractTable, ::RowDimUnknown, limit, offset)
    println(io, "\n⋮")
    print(io, "with more rows.")
end

function print_row_footer(io, tbl::AbstractTable, ::HasRowDim, limit, offset)
    println(io, "\n⋮")
    if offset > 0
        @printf(io, "with %d more rows (skipped the first %d rows).",
                nrow(tbl)-(limit+offset),
                offset
        )
    else
        @printf(io, "with %d more rows.", nrow(tbl)-limit)
    end
end

function show_tbl_header(io, tbl, maxwidths, rightmost, rowlabel)
    rowmaxwidth = maxwidths[end]
    flds = fields(tbl)
    @printf(io, "│ %s", rowlabel)
    pad(io, rowmaxwidth - ourstrwidth(rowlabel))
    print(io, " │ ")
    for j in 1:rightmost
        fld = flds[j]
        ourshowcompact(io, fld)
        pad(io, maxwidths[j] - ourstrwidth(fld))
        j == rightmost ? print(io, " │\n") : print(io, " │ ")
    end
    print_bounding_line(io, maxwidths, rightmost)
    return
end

function rightbound(io, maxwidths)
    availablewidth = displaysize(io)[2]
    ncols = length(maxwidths) - 1
    rowmaxwidth = maxwidths[ncols + 1]
    totalwidth = rowmaxwidth + 4
    rightmost = 1
    for j in 1:ncols
        rightmost = j
        # include 2 spaces + | character in per-column character count
        totalwidth += maxwidths[j] + 3
        totalwidth > availablewidth && (rightmost -= 1; break)
    end
    return rightmost
end

function show_tbl(io, tbl, rowlabel, displaysummary, limit, offset)
    if ncol(tbl) > 0
        displaysummary && println(io, summary(tbl))
        maxwidths = getmaxwidths(tbl, rowlabel, limit, offset)
        rightmost = rightbound(io, maxwidths)
        show_tbl_header(io, tbl, maxwidths, rightmost, rowlabel)
        show_tbl_rows(io, tbl, maxwidths, rightmost, rowlabel, limit, offset)
    else
        @printf(io, "An empty %s", typeof(tbl))
    end
    return
end

# 1 space for line-initial | + length of field + 2 spaces + trailing |
printedwidth(maxwidths) = foldl((x,y)->x+y+3, 1, maxwidths)

function _ci_show(io::IO, tbl::AbstractTable, rowlabel = :Row,
                   displaysummary = true, limit = 10, offset = 0)
    show_tbl(io, tbl, rowlabel, displaysummary, limit, offset)
end

_ci_show(tbl::AbstractTable, limit, offset) = show(STDOUT, tbl, :Row, true, limit, offset)