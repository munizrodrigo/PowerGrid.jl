const default_settings = Dict{Symbol, Any}(
    :sbase_kva => 1e5,
    :vm_lb => 0.92,
    :vm_ub => 1.05,
    :tm_step => 0.00625
)

function fill_settings!(settings::Dict{Symbol, Any})
    for (key, value) in default_settings
        if !haskey(settings, key)
            settings[key] = value
        end
    end
end