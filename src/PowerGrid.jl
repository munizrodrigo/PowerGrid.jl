module PowerGrid

using PythonCall

import PowerModels
import PowerModelsDistribution
import OrderedCollections: OrderedSet

export Grid

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
    _fill_settings!(settings)
    return _grid(grid, source, settings)
end

function _grid(grid::Grid, source::String, settings::Dict{Symbol, Any}; kwargs...)
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
        if isa(e, GraphNotRadial)
            @error("Graph is not radial")
        elseif isa(e, GraphNotConnected)
            @error("Graph is not connected")
        end
        # _generate_grid_log(grid.mat_powermodel, dirname(grid.source))
        rethrow()
    end
    _update_mat_powermodel!(grid.mat_powermodel, grid.graph)
    grid.buses = _buses(grid.graph)
    grid.branches = _branches(grid.graph)

    # grid.export_to_json = json_file -> _export_to_json(grid.eng_powermodel, json_file)
    # grid.save_powermodels = path -> _save_powermodels(grid.eng_powermodel, grid.mat_powermodel, path)
    # grid.export_powerplot = filepath -> _export_powerplot(grid.mat_powermodel, filepath)
    # grid.plot_graph = (args...; kwargs...) -> _plot_graph_with_args(grid.graph, args...; kwargs...)

    # grid.export_to_opendss = dss_file -> _export_to_opendss(grid.eng_powermodel, dss_file)
    # grid.get_substation = () -> _get_substation(grid.mat_powermodel)
    return grid
end

include("import.jl")
include("graph.jl")

function __init__()
    nx[] = pyimport("networkx")
    plotly[] = pyimport("plotly.graph_objects")
    np[] = pyimport("numpy")
    walkerlayout[] = pyimport("walkerlayout")
end

end
