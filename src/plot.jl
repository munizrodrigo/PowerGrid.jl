const default_load_attrs = ["name", "model", "configuration", "pd", "qd", "dispatchable"]
const default_gen_attrs = ["name", "model", "configuration", "pg", "qg", "pmin", "pmax", "qmin", "qmax"]
const default_shunt_attrs = ["name", "gs", "bs", "dispatchable"]
const default_storage_attrs = ["name", "configuration", "energy_rating", "r", "x", "energy", "ps", "qs", "charge_rating", "discharge_rating", "charge_efficiency", "discharge_efficiency", "p_loss", "q_loss", "qmin", "qmax"]
const default_bus_attrs = ["name", "vmin", "vmax"]
const default_branch_attrs = ["name", "br_r", "br_x"]
const default_transformer_attrs = ["name", "configuration", "tm_lb", "tm_ub", "tm_set", "tm_step", "tm_fix", "sm_ub"]

const bus_marker = Dict(
    "color" => "black",
    "size" => 16,
    "line_width" => 2,
    "line_color" => "black"
)

const connector_line = Dict(
    "width" => 2.5,
    "color" => "gray",
    "dash" => "dot"
)

const element_marker = Dict(
    "size" => 14,
    "line_width" => 1.5,
    "line_color" => "black"
)

const transformer_line = Dict(
    "width" => 2.5,
    "color" => "#CB3C33",
    "dash" => "dashdot"
)

const branch_line = Dict(
    "width" => 2.5,
    "color" => "black",
)

const margin = Dict(
    "b" => 20,
    "l" => 5,
    "r" => 5,
    "t" => 40
)

const config = Dict(
    "displaylogo" => false,
    "modeBarButtonsToRemove" => ["select", "select2d", "lasso2d"],
    "toImageButtonOptions" => Dict(
        "format" => "svg",
        "filename" => "grid",
        "height" => 500,
        "width" => 700,
        "scale" => 1
    )
)

function _plot_graph(graph, filepath; bus_attrs=default_bus_attrs, branch_attrs=default_branch_attrs, transformer_attrs=default_transformer_attrs, 
    load_attrs=default_load_attrs, gen_attrs=default_gen_attrs, shunt_attrs=default_shunt_attrs, storage_attrs=default_storage_attrs, fig_size=nothing)
    data = pylist()

    for edge in graph.edges()
        edge_x = PyList()
        edge_y = PyList()
        x0, y0 = graph.nodes[edge[0]]["pos"]
        x1, y1 = graph.nodes[edge[1]]["pos"]

        is_transformer = pyconvert(Bool, graph.edges[edge]["is_transformer"])
        if is_transformer
            line = PyDict(transformer_line)
            marker = PyDict(Dict("opacity" => 0.0, "color" => "#CB3C33"))
            text = "<b><em>Transformer</em></b><br>"
            attrs = transformer_attrs
        else
            line = PyDict(branch_line)
            marker = PyDict(Dict("opacity" => 0.0, "color" => "black"))
            text = "<b><em>Branch</em></b><br>"
            attrs = branch_attrs
        end

        for attr in attrs
            text *= "$(_fmt_attr_name(attr)): $(_fmt_attr_value(graph.edges[edge][attr]))<br>"
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

        mid_node_trace = Scatter(
            x=pylist([(x0 + x1) / 2]),
            y=pylist([(y0 + y1) / 2]),
            mode="markers",
            hoverinfo="text",
            marker=marker,
            text=text
        )

        data.append(edge_trace)
        data.append(mid_node_trace)
    end

    node_x = PyList()
    node_y = PyList()
    node_text = PyList()
    for node in graph.nodes()
        x, y = graph.nodes[node]["pos"]

        text = "<b><em>Bus $(node)</em></b><br>"

        for attr in bus_attrs
            text *= "$(_fmt_attr_name(attr)): $(_fmt_attr_value(graph.nodes[node][attr]))<br>"
        end

        push!(node_x, x)
        push!(node_y, y)
        push!(node_text, pystr(text))
    end

    node_trace = Scatter(
        x=node_x,
        y=node_y,
        mode="markers",
        hoverinfo="text",
        marker=PyDict(bus_marker),
        text=node_text
    )

    data.append(node_trace)

    _add_node_elements!(data, graph; load_attrs=load_attrs, gen_attrs=gen_attrs, shunt_attrs=shunt_attrs, storage_attrs=storage_attrs)

    annotations = PyList(
        [
            PyDict(
                Dict(
                    "text" => "Bus Number: $(graph.number_of_nodes())",
                    "font" => PyDict(Dict("color" => "black")),
                    "showarrow" => false,
                    "xref" => "paper",
                    "yref" => "paper",
                    "x" => 0.005,
                    "y" => -0.002
                )
            )
        ]
    )

    xaxis = PyDict(Dict("showgrid" => false, "zeroline" => false, "showticklabels" => false))
    yaxis = PyDict(Dict("showgrid" => false, "zeroline" => false, "showticklabels" => false))

    layout = Layout(
        title="Grid Name: $(graph.graph["name"])",
        titlefont_size=16,
        titlefont_color="black",
        showlegend=false,
        plot_bgcolor="white",
        hovermode="closest",
        margin=PyDict(margin),
        annotations=annotations,
        xaxis=xaxis,
        yaxis=yaxis
    )

    fig = Figure(
        data=data,
        layout=layout
    )

    if !isnothing(fig_size)
        (width, height) = fig_size
        fig.update_layout(
            autosize=false,
            width=width,
            height=height,
        )
    end

    fig_config = config
    fig_config["modeBarButtonsToRemove"] = PyList(fig_config["modeBarButtonsToRemove"])
    fig_config["toImageButtonOptions"] = PyDict(fig_config["toImageButtonOptions"])

    fig.write_html(filepath, config=PyDict(fig_config))
end

function _add_node_elements!(data, graph; scale=0.05, load_attrs=default_load_attrs, gen_attrs=default_gen_attrs, shunt_attrs=default_shunt_attrs, storage_attrs=default_storage_attrs)
    for node in graph.nodes()
        x0, y0 = graph.nodes[node]["pos"]

        element_graph = Graph()
        element_color = PyList()
        element_symbol = PyList()
        element_text = PyList()

        for element_type in ["gen", "load", "shunt", "storage"]
            if element_type in graph.nodes[node].keys()
                for element in graph.nodes[node][element_type].values()
                    node_index = element_graph.number_of_nodes() + 1
                    element_graph.add_node(node_index)

                    if element_type == "gen"
                        push!(element_color, pystr("#389826"))
                        if Bool(graph.nodes[node]["name"] == pystr("sourcebus"))
                            push!(element_symbol, pystr("circle-x"))
                        else
                            push!(element_symbol, pystr("circle-dot"))
                        end
                        text = "<b><em>Generator</em></b><br>"
                        attrs = gen_attrs
                    elseif element_type == "load"
                        push!(element_color, pystr("#CB3C33"))
                        push!(element_symbol, pystr("triangle-down"))
                        text = "<b><em>Load</em></b><br>"
                        attrs = load_attrs
                    elseif element_type == "shunt"
                        push!(element_color, pystr("#9558B2"))
                        push!(element_symbol, pystr("diamond-tall"))
                        text = "<b><em>Shunt</em></b><br>"
                        attrs = shunt_attrs
                    else
                        push!(element_color, pystr("#4063D8"))
                        push!(element_symbol, pystr("square"))
                        text = "<b><em>Storage</em></b><br>"
                        attrs = storage_attrs
                    end

                    for attr in attrs
                        text *= "$(_fmt_attr_name(attr)): $(_fmt_attr_value(element[attr]))<br>"
                    end

                    push!(element_text, pystr(text))

                end
            end
        end

        number_of_nodes = pyconvert(Int64, element_graph.number_of_nodes())
        
        if number_of_nodes > 0
            pos = circular_layout(element_graph; scale=scale, center=pylist([x0,y0]))
            if number_of_nodes == 1
                pos[1] = (1 + scale) * pos[1]
            end
            set_node_attributes(element_graph, pos, "pos")

            element_node_x = []
            element_node_y = []
            element_edge_x = []
            element_edge_y = []
            for element_node in element_graph.nodes()
                x, y = element_graph.nodes[element_node]["pos"]

                push!(element_node_x, x)
                push!(element_node_y, y)

                push!(element_edge_x, x0)
                push!(element_edge_x, x)
                push!(element_edge_x, pybuiltins.None)

                push!(element_edge_y, y0)
                push!(element_edge_y, y)
                push!(element_edge_y, pybuiltins.None)
            end

            element_edge_trace = Scatter(
                x=element_edge_x,
                y=element_edge_y,
                line=PyDict(connector_line),
                hoverinfo="none",
                mode="lines"
            )

            data.insert(1, element_edge_trace)

            marker = element_marker
            marker["color"] = element_color
            marker["symbol"] = element_symbol
            marker = PyDict(marker)

            element_node_trace = Scatter(
                x=element_node_x,
                y=element_node_y,
                mode="markers",
                marker=marker,
                hoverinfo="text",
                text=element_text
            )

            data.append(element_node_trace)
        end
    end
end

function _fmt_attr_name(attr_name)
    return "<b>$(attr_name)</b>"
end

function _fmt_attr_value(attr_value)
    if Bool(attr_value.__class__ ==  @py np[].matrix)
        attr_value = pystr("<br>") + array2string(attr_value; precision=4, suppress_small=true, formatter=PyDict(Dict(pystr("float") => pystr("{: 0.4f}").format)))
        attr_value = attr_value.replace(pystr("\n"), pystr("<br>"))
    elseif Bool(attr_value.__class__ ==  @py list)
        attr_value = array(attr_value)
        attr_value = array2string(attr_value; precision=4, suppress_small=true, formatter=PyDict(Dict(pystr("float") => pystr("{: 0.6f}").format)))
    elseif Bool(attr_value.__class__ ==  @py float)
        attr_value = pystr("{:.6f}").format(attr_value)
    end
    return attr_value
end