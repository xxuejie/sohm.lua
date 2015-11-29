local extract_id = function(model, data, db)
  local id = data.id
  if id then
    return id
  else
    return db:call("INCR", model.name .. "_id")
  end
end

local _init = function(model, schema)
  model.attribute_functions["id"] = extract_id
end

return {
  _init = _init
}
