function _generate_grid_log(mat_powermodel, path; use_walkerlayout=false)
    bus_lookup = mat_powermodel["bus_lookup"]
    bus_lookup = Dict(value => key for (key, value) in bus_lookup)

    source = _get_substation(mat_powermodel)

    graph = _generate_basic_graph(mat_powermodel, use_walkerlayout)

    digraph = bfs_tree(graph, source)

    fig = _generate_basic_graph_figure(graph, digraph, bus_lookup)

    fig_config = config
    fig_config["modeBarButtonsToRemove"] = PyList(fig_config["modeBarButtonsToRemove"])
    fig_config["toImageButtonOptions"] = PyDict(fig_config["toImageButtonOptions"])

    fig.write_html(joinpath(path, "log_graph_plot.html"), config=PyDict(fig_config))

    log_graph = _generate_log_graph_text(graph, digraph, bus_lookup)

    open(joinpath(path, "log_graph.txt"), "w") do file
        write(file, log_graph)
    end

    @warn("A grid log is present in $(path)")
end

function _generate_basic_graph(mat_powermodel, use_walkerlayout)
    graph = Graph()

    for (_, bus) in mat_powermodel["bus"]
        i = bus["bus_i"]
        graph.add_node(i)
    end
    for (_, branch) in mat_powermodel["branch"]
        (i,j) = (branch["f_bus"], branch["t_bus"])
        graph.add_edge(i,j)
    end
    for (_, transformer) in mat_powermodel["transformer"]
        (i,j) = (transformer["f_bus"], transformer["t_bus"])
        graph.add_edge(i,j)
    end

    if use_walkerlayout
        source = _get_substation(mat_powermodel)
        digraph = bfs_tree(graph, source)
        pos = walker_layout(; graph=digraph, root_node=source)
    else
        pos = kamada_kawai_layout(graph)
    end
    set_node_attributes(graph, pos, "pos")

    return graph
end

function _generate_basic_graph_figure(graph, digraph, bus_lookup)
    data = pylist()

    for edge in graph.edges()
        i = edge[0]
        j = edge[1]
        edge_x = PyList()
        edge_y = PyList()
        x0, y0 = graph.nodes[i]["pos"]
        x1, y1 = graph.nodes[j]["pos"]


        if (i,j) in digraph.edges() || (j,i) in digraph.edges()
            line = PyDict(Dict("width" => 2.5, "color" => "black"))
        else
            line = PyDict(Dict("width" => 2.5, "color" => "red"))
        end

        push!(edge_x, x0)
        push!(edge_x, x1)
        push!(edge_x, pybuiltins.None)

        push!(edge_y, y0)
        push!(edge_y, y1)
        push!(edge_y, pybuiltins.None)

        edge_trace = Scatter(
            x=edge_x,
            y=edge_y,
            line=line,
            hoverinfo="none",
            mode="lines"
        )

        data.append(edge_trace)
    end

    for node in graph.nodes()
        x, y = graph.nodes[node]["pos"]

        text = "<b>Bus $(node)<b>"
        if pyconvert(Int64, node) in keys(bus_lookup)
            text *= "<br>DSS Node: $(bus_lookup[pyconvert(Int64, node)])"
        end

        if node in digraph.nodes()
            color = "black"
        else
            color = "red"
        end

        node_trace = Scatter(
            x=[x],
            y=[y],
            mode="markers",
            hoverinfo="text",
            marker=PyDict(Dict(
                "color" => color,
                "size" => 16,
                "line_width" => 2,
                "line_color" => color
            )),
            text=text
        )

        data.append(node_trace)
    end

    xaxis = PyDict(Dict("showgrid" => false, "zeroline" => false, "showticklabels" => false))
    yaxis = PyDict(Dict("showgrid" => false, "zeroline" => false, "showticklabels" => false))

    layout = Layout(
        titlefont_size=16,
        titlefont_color="black",
        showlegend=false,
        plot_bgcolor="white",
        hovermode="closest",
        margin=PyDict(margin),
        xaxis=xaxis,
        yaxis=yaxis
    )

    fig = Figure(
        data=data,
        layout=layout
    )

    return fig
end

function _generate_log_graph_text(graph, digraph, bus_lookup)
    log_graph = "DSS Nodes to remove:\n"

    for i in graph.nodes()
        if !(i in digraph.nodes())
            if pyconvert(Int64, i) in keys(bus_lookup)
                log_graph *= "- $(bus_lookup[pyconvert(Int64, i)])\n"
            end
        end
    end

    log_graph *= "\nDSS Edges to remove:\n"

    for (i,j) in graph.edges()
        if !((i,j) in digraph.edges()) && !((j,i) in digraph.edges())
            if pyconvert(Int64, i) in keys(bus_lookup) && pyconvert(Int64, j) in keys(bus_lookup)
                log_graph *= "- ($(bus_lookup[pyconvert(Int64, i)]) , $(bus_lookup[pyconvert(Int64, j)]))\n"
            elseif pyconvert(Int64, i) in keys(bus_lookup)
                log_graph *= "- ($(bus_lookup[pyconvert(Int64, i)]) , virtual_transformer_bus.$j)\n"
            elseif pyconvert(Int64, j) in keys(bus_lookup)
                log_graph *= "- (virtual_transformer_bus.$i , $(bus_lookup[pyconvert(Int64, j)]))\n"
            end
        end
    end

    return log_graph
end