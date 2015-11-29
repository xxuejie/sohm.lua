local util = require "sohm.util"

local INDEX_SHARDS = 32

local all = function(self, db)
  local iter = nil
  local i = 1
  return function()
    while i <= INDEX_SHARDS do
      if not iter then
        iter = self:find(db, "all", i):iter(db)
      end
      local item = iter()
      if item then
        return item
      else
        i = i + 1
        iter = nil
      end
    end
    return nil
  end
end

local hash_id = function(data)
  local id = tostring(data.id)
  local sum = 0
  -- Notice that the only valid use case for this use case, is to loop through
  -- all shards and fetch all elements. So consistent hashing is not a strong
  -- requirement here. However, using consistent hashing can indeed prevent
  -- us from refreshing `all` index each time we are saving this model. The
  -- main point is: we are free to change the hashing function here at any time,
  -- there will not be any critical problems to our database.
  for i = 1, string.len(id) do
    sum = sum + string.byte(id, i)
  end
  return sum % INDEX_SHARDS + 1
end

local _init = function(model, schema)
  if type(model.indices) ~= "table" then
    error("Please enable index plugin first!")
  end
  model.indices[#model.indices + 1] = "all"
  model.index_functions["all"] = hash_id
end

return {
  _init = _init,
 all = all
}
