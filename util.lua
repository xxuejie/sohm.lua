local util = {}

util.script = function(db, script, sha, ...)
  local res, err = db:call("EVALSHA", sha, ...)
  if err and string.find(err, "NOSCRIPT") then
    res, err = db:call("EVAL", script, ...)
  end
  return res, err
end

util.zip = function(values)
  local res = {}
  for i = 1, #values, 2 do
    res[values[i]] = values[i + 1]
  end
  return res
end

util.ensure_id = function(id_or_data)
  if type(id_or_data) == "table" then
    return id_or_data.id
  else
    return id_or_data
  end
end

util.ensure_data = function(model, db, id_or_data)
  if type(id_or_data) == "table" then
    return id_or_data
  else
    return model:fetch(db, id_or_data)
  end
end

util.array_contain = function(arr, elem)
  for _, val in ipairs(arr) do
    if val == elem then return true end
  end
  return false
end

util.array_diff = function(a, b)
  res = {}
  for _, val in ipairs(a) do
    if not util.array_contain(b, val) then
      res[#res + 1] = val
    end
  end
  return res
end

util.array_slice = function(arr, size)
  local i = 1
  return function ()
    local res = {}
    local limit = math.min(i + size - 1, #arr)
    while i <= limit do
      res[#res + 1] = arr[i]
      i = i + 1
    end
    if #res > 0 then
      return res
    else
      return nil
    end
  end
end

return util
