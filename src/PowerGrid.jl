module PowerGrid

using PythonCall
using JSON

import PowerModels
import PowerModelsDistribution
import OrderedCollections: OrderedSet

export Grid
export edit_load!, edit_gen!

include("exceptions.jl")
include("defaults.jl")
include("python.jl")

mutable struct Grid
    source::String
    settings::Dict{Symbol, Any}
    eng_powermodel::Dict
    mat_powermodel::Dict
    graph::Py
    buses::OrderedSet{Int64}
    branches::OrderedSet{Tuple{Int64,Int64}}
    get_substation::Function
    export_to_opendss::Function
    save_powermodels::Function
    plot_graph::Function
    Grid(source::String) = _grid(new(), source)
    Grid(source::String, settings::Dict{Symbol, Any}; kwargs...) = _grid(new(), source, settings; kwargs...)
end

function _grid(grid::Grid, source::String)
    settings = Dict{Symbol, Any}()
    _add_imported_settings!(settings, source; print_output=false)
    _fill_settings!(settings)
    return _grid(grid, source, settings)
end

function _grid(grid::Grid, source::String, settings::Dict{Symbol, Any}; kwargs...)
    _add_imported_settings!(settings, source; print_output=true)
    _fill_settings!(settings)

    grid.source = source
    grid.settings = settings

    if endswith(source, ".dss")
        grid.eng_powermodel, grid.mat_powermodel = _import_from_opendss(source; settings...)
    else
        throw(InvalidSource("Only OpenDSS files are valid sources"))
    end

    try
        grid.graph = _graph(grid.mat_powermodel)
    catch e
        if isa(e, Union{GraphNotRadial,GraphNotConnected})
            use_walkerlayout = true
            if isa(e, GraphNotRadial)
                @error("Graph is not radial")
            else
                @error("Graph is not connected")
                use_walkerlayout = false
            end
            _generate_grid_log(grid.mat_powermodel, dirname(grid.source); use_walkerlayout=use_walkerlayout)
        end
        rethrow()
    end
    _update_mat_powermodel!(grid.mat_powermodel, grid.graph)
    grid.buses = _buses(grid.graph)
    grid.branches = _branches(grid.graph)
    grid.get_substation = () -> _get_substation(grid.mat_powermodel)

    grid.save_powermodels = path -> _save_powermodels(grid.eng_powermodel, grid.mat_powermodel, path)
    grid.export_to_opendss = dss_file -> _export_to_opendss(grid.eng_powermodel, dss_file)

    grid.plot_graph = (path; kwargs...) -> _plot_graph(grid.graph, path; kwargs...)

    return grid
end

function Base.show(io::IO, g::Grid)
    print(io, "Grid with $(length(keys(g.mat_powermodel["bus"]))) buses, $(length(keys(g.mat_powermodel["branch"])) + length(keys(g.mat_powermodel["transformer"]))) branches, $(length(keys(g.mat_powermodel["load"]))) loads, $(length(keys(g.mat_powermodel["gen"]))) generators and $(length(keys(g.mat_powermodel["shunt"]))) shunt capacitors")
end

include("import.jl")
include("graph.jl")
include("export.jl")
include("plot.jl")
include("log.jl")
include("edit.jl")

function __init__()
    nx[] = pyimport("networkx")
    plotly[] = pyimport("plotly.graph_objects")
    np[] = pyimport("numpy")
    walkerlayout[] = pyimport("walkerlayout")
end

end
