function _graph(mat_powermodel)
    source = _get_substation(mat_powermodel)

    graph = Graph(name=mat_powermodel["name"], settings=_convert_to_py(mat_powermodel["settings"]))

    for (_, bus) in mat_powermodel["bus"]
        i = bus["bus_i"]
        graph.add_node(i)
        attrs = pydict()
        attrs[i] = _convert_to_py(bus)
        set_node_attributes(graph, attrs)
    end

    for (_, branch) in mat_powermodel["branch"]
        (i,j) = (branch["f_bus"], branch["t_bus"])
        graph.add_edge(i,j)
        attrs = pydict()
        attrs[(i,j)] = _convert_to_py(branch)
        attrs[(i,j)][pystr("is_transformer")] = pybool(false)
        set_edge_attributes(graph, attrs)
    end

    for (_, transformer) in mat_powermodel["transformer"]
        (i,j) = (transformer["f_bus"], transformer["t_bus"])
        graph.add_edge(i,j)
        attrs = pydict()
        attrs[(i,j)] = _convert_to_py(transformer)
        attrs[(i,j)][pystr("is_transformer")] = pybool(true)
        set_edge_attributes(graph, attrs)
    end

    for (index, load) in mat_powermodel["load"]
        i = load["load_bus"]
        if !("load" in graph.nodes[i])
            graph.nodes[i]["load"] = pydict()
        end
        graph.nodes[i]["load"][pystr(index)] = _convert_to_py(load)
    end

    for (index, shunt) in mat_powermodel["shunt"]
        i = shunt["shunt_bus"]
        if !("shunt" in graph.nodes[i])
            graph.nodes[i]["shunt"] = pydict()
        end
        graph.nodes[i]["shunt"][pystr(index)] = _convert_to_py(shunt)
    end

    for (index, gen) in mat_powermodel["gen"]
        i = gen["gen_bus"]
        if !("gen" in graph.nodes[i])
            graph.nodes[i]["gen"] = pydict()
        end
        graph.nodes[i]["gen"][pystr(index)] = _convert_to_py(gen)
    end

    for (index, storage) in mat_powermodel["storage"]
        i = storage["storage_bus"]
        if !("storage" in graph.nodes[i])
            graph.nodes[i]["storage"] = pydict()
        end
        graph.nodes[i]["storage"][pystr(index)] = _convert_to_py(storage)
    end

    if !_is_radial(graph, source)
        throw(GraphNotRadial("Graph is not radial"))
    end
    
    if !_is_connected(graph)
        throw(GraphNotConnected("Graph is not connected"))
    end

    digraph = bfs_tree(graph, source)

    digraph.graph = graph.graph

    for i in digraph.nodes()
        attrs = Dict(i => graph.nodes[i])
        set_node_attributes(digraph, attrs)
    end

    for (i,j) in digraph.edges()
        if (i,j) in graph.edges
            attrs = Dict((i,j) => graph.edges[i, j])
            set_edge_attributes(digraph, attrs)
        else
            attrs = Dict((i,j) => graph.edges[j, i])
            set_edge_attributes(digraph, attrs)
        end
    end

    pos = walker_layout(; graph=digraph, root_node=source)
    set_node_attributes(digraph, pos, "pos")
    
    return digraph
end

function _get_substation(mat_powermodel)
    substation = filter(
        ((key, value),) -> value["name"] == "sourcebus", mat_powermodel["bus"]
        )
        substation = parse(Int64, first(keys(substation)))
    return substation
end


function _is_radial(graph, source)
    try
        find_cycle(graph, source) 
        return false
    catch e
        if isa(e, PyException) && pyisinstance(e, nx[].NetworkXNoCycle)
            return true
        end
    end
end

function _is_connected(graph)
    return Bool(is_connected(graph))
end
