function _import_from_opendss(dss_file::String; settings...)
    eng_powermodel = _generate_eng_powermodel(dss_file; settings...)

    mat_powermodel = _generate_mat_powermodel(eng_powermodel; settings...)

    return eng_powermodel, mat_powermodel
end

function _generate_eng_powermodel(dss_file::String; settings...)
    (; sbase_kva, vm_lb, vm_ub) = (; settings...)

    eng_powermodel = PowerModelsDistribution.parse_file(dss_file; make_pu=false, import_all=true)

    @info("Using sbase_kva=$(sbase_kva) (basemva=$(sbase_kva / 1e3)) instead of default value.")

    eng_powermodel["settings"]["sbase_default"] = sbase_kva

    PowerModelsDistribution.apply_voltage_bounds!(eng_powermodel; vm_lb=vm_lb, vm_ub=vm_ub)

    _make_sources_lossless!(eng_powermodel)

    dss_ext_file = first(splitext(dss_file)) * ".dsse"

    if isfile(dss_ext_file)
        _add_dss_extensions!(eng_powermodel, dss_ext_file)
    else
        @info("No OpenDSS extension .dsse file was found. Using only the main .dss file.")
    end

    return eng_powermodel
end

function _generate_mat_powermodel(eng_powermodel; settings...)
    regulators = _get_regulators(eng_powermodel)
    transformer_losses = _recover_transformer_losses(eng_powermodel)
    eng_powermodel_lossless = _make_transformer_lossless(eng_powermodel)
    mat_powermodel = PowerModelsDistribution.transform_data_model(eng_powermodel_lossless)
    _add_transformer_losses!(mat_powermodel, transformer_losses)
    _add_transformer_settings!(mat_powermodel; settings...)
    _unfix_regulators!(mat_powermodel, regulators)

    return mat_powermodel
end

function _make_sources_lossless!(eng_powermodel)
    for (_, source) in eng_powermodel["voltage_source"]
        for (i, _) in pairs(source["rs"])
            source["rs"][i] = 0.0
        end

        for (i, _) in pairs(source["xs"])
            source["xs"][i] = 0.0
        end

        delete!(source["dss"], "mvasc3")

        source["dss"]["z0"] = "0,0"
        source["dss"]["z1"] = "0,0"
    end
end

function _add_dss_extensions!(eng_powermodel, dss_ext_file)
    dss_ext = _import_dss_extensions(dss_ext_file)
    if haskey(dss_ext, "generator")
        _add_gen_extensions!(eng_powermodel, dss_ext)
    end
    if haskey(dss_ext, "load")
        _add_load_extensions!(eng_powermodel, dss_ext)
    end
end

function _import_dss_extensions(dss_ext_file)
    cmds = _parse_dss_entensions_cmds(dss_ext_file)
    dss_ext = Dict{String, Dict}()
    for cmd in cmds
        element_and_attrs = [strip(c) for c in split(cmd, " ")]
        element = first(element_and_attrs)
        attrs = element_and_attrs[2:end]
        class, name = split(element, ".")
        if !haskey(dss_ext, class)
            dss_ext[class] = Dict{String, Dict}()
        end
        dss_ext[class][name] = Dict{String, String}()
        for attr in attrs
            attr_name, attr_value = split(attr, "=")
            dss_ext[class][name][attr_name] = attr_value
        end
    end
    return dss_ext
end

function _parse_dss_entensions_cmds(dss_ext_file)
    local dss_ext_cmds
    open(dss_ext_file) do file
        dss_ext_cmds = readlines(file)
    end
    dss_ext_valid_cmds = Vector{String}()
    for cmd in dss_ext_cmds
        if startswith(cmd, "edit")
            push!(dss_ext_valid_cmds, strip(cmd[length("edit")+1:end]))
        end
    end
    return dss_ext_valid_cmds
end

function _add_gen_extensions!(eng_powermodel, dss_ext)
    attr_map = Dict{String, String}(
        "minkw" => "pg_lb",
        "maxkw" => "pg_ub",
        "minkvar" => "qg_lb",
        "maxkvar" => "qg_ub"
    )
    for (gen_name, gen_attrs) in dss_ext["generator"]
        @assert haskey(eng_powermodel["generator"], gen_name)
        for (attr_name, attr_value) in gen_attrs
            @assert haskey(attr_map, attr_name)
            for phase in eachindex(eng_powermodel["generator"][gen_name][attr_map[attr_name]])
                eng_powermodel["generator"][gen_name][attr_map[attr_name]][phase] = parse(Float64, attr_value) / eng_powermodel["generator"][gen_name]["phases"]
            end
        end
    end
end

function _add_load_extensions!(eng_powermodel, dss_ext)
    #TODO Implement load extensions
end

function _get_regulators(eng_powermodel)
    regulators = Vector{String}()
    for (transformer_name, transformers_attrs) in eng_powermodel["transformer"]
        if haskey(transformers_attrs, "controls")
            push!(regulators, transformer_name)
        end
    end
    return regulators
end

function _recover_transformer_losses(eng_powermodel)
    mat_powermodel = PowerModelsDistribution.transform_data_model(eng_powermodel)
    transformer_losses = Dict{String, Any}()
    for (_, branch) in mat_powermodel["branch"]
        if startswith(branch["source_id"], "_virtual_branch.transformer.")
            transformer_name = split(branch["source_id"], ".")
            transformer_name = transformer_name[end]
            transformer_name = rsplit(transformer_name, "_"; limit=2)
            transformer_name = transformer_name[1]
            if !(transformer_name in keys(transformer_losses))
                transformer_losses[transformer_name] = Dict{String, Any}()
                transformer_losses[transformer_name]["br_r"] = branch["br_r"]
                transformer_losses[transformer_name]["br_x"] = branch["br_x"]
            else
                transformer_losses[transformer_name]["br_r"] += branch["br_r"]
                transformer_losses[transformer_name]["br_x"] += branch["br_x"]
            end
        end
    end
    return transformer_losses
end

function _make_transformer_lossless(eng_powermodel)
    eng_powermodel_lossless = deepcopy(eng_powermodel)
    for (_, transformer) in eng_powermodel_lossless["transformer"]
        for (i, _) in pairs(transformer["rw"])
            transformer["rw"][i] = 0.0
        end

        for (i, _) in pairs(transformer["xsc"])
            transformer["xsc"][i] = 0.0
        end

        if !haskey(transformer, "dss")
            transformer["dss"] = Dict()
        end
        transformer["dss"]["%r"] = "0.0"
        transformer["dss"]["xhl"] = "0"
    end
    return eng_powermodel_lossless
end

function _add_transformer_losses!(mat_powermodel, transformer_losses)
    transformer_branch = max(map((b) -> parse(Int64, b), collect(keys(mat_powermodel["branch"])))...) + 1

    index_to_remove = []
    for (index, transformer) in mat_powermodel["transformer"]
        (_, _, transformer_name, id) = split(transformer["source_id"], ".")
        if transformer_name in keys(transformer_losses)
            if id == "2"
                f_bus = transformer["f_bus"]
                t_bus = transformer["t_bus"]
                mat_powermodel["branch"]["$(transformer_branch)"] = transformer_losses[transformer_name]
                mat_powermodel["branch"]["$(transformer_branch)"]["f_bus"] = f_bus
                mat_powermodel["branch"]["$(transformer_branch)"]["t_bus"] = t_bus
                mat_powermodel["branch"]["$(transformer_branch)"]["name"] = transformer["name"]
                push!(index_to_remove, index)
                transformer_branch += 1
            else
                mat_powermodel["transformer"][index]["br_r"] = transformer_losses[transformer_name]["br_r"]
                mat_powermodel["transformer"][index]["br_x"] = transformer_losses[transformer_name]["br_x"]
            end
        end
    end
    for index in index_to_remove
        delete!(mat_powermodel["transformer"], index)
    end
end

function _add_transformer_settings!(mat_powermodel; settings...)
    (; tm_step) = (; settings...)
    if !isnothing(tm_step)
        for (index, _) in mat_powermodel["transformer"]
            for phase in eachindex(mat_powermodel["transformer"]["$(index)"]["tm_step"])
                mat_powermodel["transformer"]["$(index)"]["tm_step"][phase] = tm_step
            end
        end
    end
    return nothing
end

function _unfix_regulators!(mat_powermodel, regulators)
    for (transformer_name, transformers_attrs) in mat_powermodel["transformer"]
        for regulator in regulators
            if occursin(regulator, transformers_attrs["source_id"])
                for phase in eachindex(mat_powermodel["transformer"]["$transformer_name"]["tm_fix"])
                    mat_powermodel["transformer"]["$transformer_name"]["tm_fix"][phase] = false
                end
                break
            end
        end
    end
    return nothing
end