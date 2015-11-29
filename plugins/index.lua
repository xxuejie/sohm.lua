local collection = require "sohm.collection"
local util = require "sohm.util"

local to_index_key = function(name, att, val)
  return name .. ":_indices:" .. att .. ":" .. tostring(val)
end

local extract_indices = function(name, indices, index_functions, data)
  local arr = {}
  for _, att in ipairs(indices) do
    local vals
    local f = index_functions[att]
    if type(f) == "function" then
      vals = f(data)
    else
      vals = data[att]
    end
    if vals then
      -- There's a small defect: if an index value is already a table,
      -- we have to wrap it in another table, otherwise we would only
      -- reads its attributes out of the table. However, in reality this
      -- shouldn't be a problem, since it's very rare we want to use a
      -- table directly as an index value.
      if type(vals) ~= "table" then vals = { vals } end

      for _, val in ipairs(vals) do
        arr[#arr + 1] = to_index_key(name, att, val)
      end
    end
  end
  return arr
end

-- Ideally, you should refresh index in an async worker thread for maxium
-- performance, that's the reason this is a separate function from save.
-- You don't need to call this when you don't need find.
local refresh = function(self, db, id_or_data)
  local data = util.ensure_data(self, db, id_or_data)
  local id = data.id
  local indices = extract_indices(self.name, self.indices,
                                  self.index_functions, data)
  local memo_key = self.name .. ":" .. data.id .. ":_indices"
  local current_indices = db:call("SMEMBERS", memo_key)
  local remove_indices = util.array_diff(current_indices, indices)

  for _, index in ipairs(indices) do
    db:queue("SADD", memo_key, index)
    db:queue("SADD", index, id)
  end
  for _, index in ipairs(remove_indices) do
    db:queue("SREM", index, id)
    db:queue("SREM", memo_key, index)
  end
  local _, err = db:commit()
  return err
end

local find = function(self, db, index, val)
  if not util.array_contain(self.indices, index) then
    return nil, "NOINDEX: Index " .. index .. " is not available!"
  end
  local key = to_index_key(self.name, index, val)
  return collection.set(key, self.name, self)
end

local _init = function(model, schema)
  local dynamic_methods = {}
  model.indices = schema.indices or {}
  model.index_functions = schema.index_functions or {}
  for _, reference in ipairs(schema.references or {}) do
    local id_field = reference .. "_id"
    model.indices[#model.indices + 1] = id_field
    dynamic_methods[reference] = function(self, db, id_or_data, model)
      local data = util.ensure_data(self, db, id_or_data)
      local id = data[id_field]
      if id then
        return model:fetch(db, id)
      else
        return nil
      end
    end
    dynamic_methods["set_" .. reference] = function(self, db, data,
                                                    target_id_or_data)
      local target_id = util.ensure_id(target_id_or_data)
      data[id_field] = target_id
    end
  end
  return dynamic_methods
end

return {
  _init = _init,
  find = find,
  refresh = refresh
}
