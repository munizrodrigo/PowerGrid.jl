const default_settings = Dict{Symbol, Any}(
    :sbase_kva => 1e5,
    :vm_lb => 0.92,
    :vm_ub => 1.05,
    :shunt_numsteps => 8,
    :tm_step => 0.00625,
    :ignore_transformer_losses => false
)

function _fill_settings!(settings::Dict{Symbol, Any})
    for (key, value) in default_settings
        if !haskey(settings, key)
            settings[key] = value
        end
    end
end