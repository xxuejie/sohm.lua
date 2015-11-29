local util = require "sohm.util"

local _batch_fetch = function(db, ids, namespace, model)
  if not ids then return nil, nil end
  for _, id in ipairs(ids) do
    local key = namespace .. ":" .. id
    db:queue("HGETALL", key)
  end
  results, err = db:commit()
  if err then
    return nil, err
  end
  local res = {}
  for idx, values in ipairs(results) do
    local data = model:_assemble(ids[idx], values)
    if data then res[#res + 1] = data end
  end
  return res, nil
end

local _fetch_iter = function(db, ids, namespace, model)
  local ids_iter = util.array_slice(ids, 1000)
  local cache_list = {}
  local i = 1
  return function()
    while cache_list[i] == nil do
      cache_list = _batch_fetch(db, ids_iter(), namespace, model)
      if cache_list == nil then
        -- We are running out of ids
        return nil
      end
      i = 1
    end
    i = i + 1
    return cache_list[i - 1]
  end
end

local generic_iter = function(self, db)
  local ids = self:ids(db)
  return _fetch_iter(db, ids, self.namespace, self.model)
end

local set_exists = function(self, db, id_or_data)
  return db:call("SISMEMBER", self.key, util.ensure_id(id_or_data)) == 1
end

local set_fetch = function(self, db, id)
  return self.model:fetch(db, id)
end

local set_ids = function(self, db)
  return db:call("SMEMBERS", self.key)
end

local set_size = function(self, db)
  return db:call("SCARD", self.key)
end

local set_methods = {
  exists = set_exists,
  fetch = set_fetch,
  ids = set_ids,
  iter = generic_iter,
  size = set_size
}

local mutable_set_add = function(self, db, id_or_data)
  local id = util.ensure_id(id_or_data)
  db:call("SADD", self.key, id)
end

local mutable_set_delete = function(self, db, id_or_data)
  local id = util.ensure_id(id_or_data)
  db:call("SREM", self.key, id)
end

local mutable_set_methods = {
  exists = set_exists,
  fetch = set_fetch,
  ids = set_ids,
  iter = generic_iter,
  size = set_size,
  add = mutable_set_add,
  delete = mutable_set_delete
}

local list_size = function(self, db)
  return db:call("LLEN", self.key)
end

local list_first = function(self, db)
  local id = db:call("LINDEX", self.key, 0)
  return self.model:fetch(db, id)
end

local list_last = function(self, db)
  local id = db:call("LINDEX", self.key, -1)
  return self.model:fetch(db, id)
end

local list_range = function(self, db, start, stop)
  local ids = db:call("LRANGE", self.key, start, stop)
  return _fetch_iter(db, ids, self.namespace, self.model)
end

local list_push = function(self, db, id_or_data)
  local id = util.ensure_id(id_or_data)
  db:call("RPUSH", self.key, id)
end

local list_pop = function(self, db, return_data)
  local id = db:call("RPOP", self.key)
  if id and return_data then
    return self.model:fetch(db, id)
  else
    return nil
  end
end

local list_unshift = function(self, db, id_or_data)
  local id = util.ensure_id(id_or_data)
  db:call("LPUSH", self.key, id)
end

local list_shift = function(self, db, return_data)
  local id = db:call("LPOP", self.key)
  if id and return_data then
    return self.model:fetch(db, id)
  else
    return nil
  end
end

local list_delete = function(self, db, id_or_data)
  local id = util.ensure_id(id_or_data)
  db:call("LREM", self.key, 0, id)
end

local list_ids = function(self, db)
  return db:call("LRANGE", self.key, 0, -1)
end

local list_swap = function(self, db, key)
  return db:call("RENAME", key, self.key)
end

local list_methods = {
  size = list_size,
  first = list_first,
  last = list_last,
  range = list_range,
  push = list_push,
  pop = list_pop,
  unshift = list_unshift,
  shift = list_shift,
  delete = list_delete,
  ids = list_ids,
  iter = generic_iter,
  swap = list_swap
}

local collection_constructor = function(methods)
  return function(key, namespace, model)
    local self = {}

    setmetatable(self, {__index = methods})

    self.key = key
    self.namespace = namespace
    self.model = model

    return self
  end
end

return {
  set = collection_constructor(set_methods),
  mutable_set = collection_constructor(mutable_set_methods),
  list = collection_constructor(list_methods)
}
