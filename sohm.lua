local collection = require "sohm.collection"
local util = require "sohm.util"

local save_script = [====[
local ctoken = redis.call('HGET', KEYS[1], '_cas')
if (not ctoken) or ctoken == ARGV[2] then
  local ntoken
  if not ctoken then
    ntoken = 1
  else
    ntoken = tonumber(ctoken) + 1
  end
  redis.call('HMSET', KEYS[1], '_sdata', ARGV[1],
             '_cas', ntoken, '_ndata', ARGV[3])
  local expire = tonumber(ARGV[4])
  if expire and expire > 0 then
    redis.call('EXPIRE', KEYS[1], expire)
  end
  return ntoken
else
  error('cas_error')
end
]====]
local save_script_sha = "02c49a51975e6c23a3f8a355af4e50f8df155bde"

local _pack_attributes = function(msgpack, model, attributes, data, db)
  local res = {}
  for _, att in ipairs(attributes) do
    local val
    local f = model.attribute_functions[att]
    if type(f) == "function" then
      val = f(model, data, db)
    else
      val = data[att]
    end
    if val then
      res[att] = val
    end
  end
  if next(res) ~= nil then
    return msgpack.pack(res)
  else
    -- NOTE: this adds a dependency for msgpack spec, however, it partly
    -- resolves the problem that array cannot be properly serialized
    -- here.
    return "\x80"
  end
end

local _unpack_attributes = function(msgpack, attributes, str, data)
  if not str then return end
  local hash = msgpack.unpack(str)
  for _, att in ipairs(attributes) do
    local val = hash[att]
    if val then data[att] = val end
  end
end

local _assemble = function(self, id, values)
  if #values == 0 then return nil end
  local hash = util.zip(values)
  local data = { id = id, _cas = hash._cas }
  _unpack_attributes(self.msgpack, self.attributes, hash._ndata, data)
  _unpack_attributes(self.msgpack, self.serial_attributes, hash._sdata, data)
  return data
end

local fetch = function(self, db, id)
  local key = self.name .. ":" .. id
  return self:_assemble(id, db:call("HGETALL", key))
end

local save = function(self, db, data, opts)
  opts = opts or {}
  local id
  local f = self.attribute_functions["id"]
  if type(f) == "function" then
    id = f(self, data, db)
  else
    id = data.id
  end
  if not id then
    return nil, "missing_id"
  end
  local key = self.name .. ":" .. id
  local ndata = _pack_attributes(self.msgpack, self, self.attributes, data, db)
  local expire = tonumber(opts.expire) or 0
  local res, err
  if opts.cas then
    local sdata = _pack_attributes(self.msgpack, self, self.serial_attributes,
                                  data, db)
    local cas = data._cas or ""
    res, err = util.script(db, save_script, save_script_sha,
                           1, key, sdata, cas, ndata, expire)
    if err then
      if string.find(err, "cas_error") then
        err = "cas_error"
      end
    else
      data._cas = res
    end
  elseif expire > 0 then
    db:queue("HSET", key, "_ndata", ndata)
    db:queue("EXPIRE", key, expire)
    _, err = db:commit()
  else
    _, err = db:call("HSET", key, "_ndata", ndata)
  end
  return data, err
end

local delete = function(self, db, id_or_data)
  local id = util.ensure_id(id_or_data)
  local key = self.name .. ":" .. id
  db:queue("DEL", key)
  for _, field in ipairs(self._tracked) do
    db:queue("DEL", key .. ":" .. field)
  end
  return db:commit()
end

local incr = function(self, db, id_or_data, counter, count)
  count = count or 1
  local id = util.ensure_id(id_or_data)
  local key = self.name .. ":" .. id .. ":" .. "_counters"
  return tonumber(db:call("HINCRBY", key, counter, count))
end

local decr = function(self, db, id_or_data, counter, count)
  count = count or 1
  return self:incr(db, id_or_data, counter, - count)
end

local key = function(self, db, id_or_data)
  local id = util.ensure_id(id_or_data)
  return self.name .. ":" .. id
end

local model = function(name, schema, msgpack)
  local self = {}
  self.name = name
  self.attributes = schema.attributes or {}
  self.serial_attributes = schema.serial_attributes or {}
  self.msgpack = msgpack
  self.attribute_functions = {}
  self._tracked = { "_counters" }

  local methods = {
    _assemble = _assemble,
    delete = delete,
    fetch = fetch,
    save = save,
    incr = incr,
    decr = decr,
    key = key
  }
  for _, plugin in ipairs(schema.plugins or {}) do
    local dynamic_methods = nil
    if type(plugin._init) == "function" then
      dynamic_methods = plugin._init(self, schema)
    end
    for name, method in pairs(plugin) do
      if name ~= "_init" and type(method) == "function" then
        methods[name] = method
      end
    end
    for name, method in pairs(dynamic_methods or {}) do
      if type(method) == "function" then
        methods[name] = method
      end
    end
  end
  for _, counter in ipairs(schema.counters or {}) do
    methods[counter] = function(self, db, id_or_data)
      local id = util.ensure_id(id_or_data)
      if not id then return 0 end
      local key = self.name .. ":" .. id .. ":" .. "_counters"
      return tonumber(db:call("HGET", key, counter)) or 0
    end
  end
  for _, set in ipairs(schema.sets or {}) do
    self._tracked[#self._tracked + 1] = set
    methods[set] = function(self, db, model)
      local key = self.name .. ":" .. id .. ":" .. set
      return collection.mutable_set(key, model.name, model)
    end
  end
  for _, list in ipairs(schema.lists or {}) do
    self._tracked[#self._tracked + 1] = list
    methods[list] = function(self, db, model)
      local key = self.name .. ":" .. id .. ":" .. list
      return collection.list(key, model.name, model)
    end
  end
  for _, collection in ipairs(schema.collections or {}) do
    local default_reference = string.lower(self.name) .. "_id"
    methods[collection] = function(self, db, id_or_data, model, reference)
      local id = util.ensure_id(id_or_data)
      reference = reference or default_reference
      return model:find(db, reference, id)
    end
  end
  for name, method in ipairs(schema.methods or {}) do
    methods[name] = method
  end

  setmetatable(self, {__index = methods})
  return self
end

return {
  model = model
}
