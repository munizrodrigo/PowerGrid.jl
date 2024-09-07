function edit_load!(grid::Grid, load_name, attr_name, attr_value; all_phases=true, update=true)
    @debug("Editing load $(load_name) attribute $(attr_name) to value $(attr_value).")

    if all_phases
        for phase in eachindex(grid.eng_powermodel["load"][load_name][attr_name])
            grid.eng_powermodel["load"][load_name][attr_name][phase] = attr_value
        end
    else
        grid.eng_powermodel["load"][load_name][attr_name] = attr_value
    end

    if update
        _update_grid!(grid)
    end

    return nothing
end

function edit_loads!(grid::Grid, loads_tuple::Vector{Tuple{AbstractString,AbstractString,Any}})
    for (load_name, attr_name, attr_value) in loads_tuple
        edit_load!(grid, load_name, attr_name, attr_value; all_phases=false, update=false)
    end

    _update_grid!(grid)

    return nothing
end

function edit_gen!(grid::Grid, gen_name, attr_name, attr_value; all_phases=true, update=true)
    @debug("Editing generator $(gen_name) attribute $(attr_name) to value $(attr_value).")

    if all_phases
        for phase in eachindex(grid.eng_powermodel["generator"][gen_name][attr_name])
            grid.eng_powermodel["generator"][gen_name][attr_name][phase] = attr_value
        end
    else
        grid.eng_powermodel["generator"][gen_name][attr_name] = attr_value
    end

    if update
        _update_grid!(grid)
    end

    return nothing
end

function edit_gens!(grid::Grid, gens_tuple::Vector{Tuple{AbstractString,AbstractString,Any}})
    for (gen_name, attr_name, attr_value) in gens_tuple
        edit_gen!(grid, gen_name, attr_name, attr_value; all_phases=false, update=false)
    end

    _update_grid!(grid)

    return nothing
end

function _update_grid!(grid::Grid)
    grid.mat_powermodel = _generate_mat_powermodel(grid.eng_powermodel; grid.settings...)
    grid.graph = _graph(grid.mat_powermodel)
    _update_mat_powermodel!(grid.mat_powermodel, grid.graph)
    return nothing
end