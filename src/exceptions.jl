struct InvalidSource <: Exception
    msg::String
end

struct GraphNotRadial <: Exception
    msg::String
end

struct GraphNotConnected <: Exception
    msg::String
end