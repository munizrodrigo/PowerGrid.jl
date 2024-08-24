const nx = Ref{Py}()
const walkerlayout = Ref{Py}()

Graph(; kwargs...) = nx[].Graph(; kwargs...)

walker_layout(args...; kwargs...) = walkerlayout[].WalkerLayouting.layout_networkx(args...; kwargs...)