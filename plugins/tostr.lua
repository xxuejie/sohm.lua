local attr_to_string = function(data)
  if not data then return "nil" end
  local attrs = {}
  for k, v in pairs(data) do
    local val
    if type(v) == "string" then
      val = "\"" .. v .. "\""
    else
      val = tostring(v)
    end
    attrs[#attrs + 1] = tostring(k) .. " = " .. val
  end
  return "{" .. table.concat(attrs, ", ") .. "}"
end

local tostr = function(self, db, data)
  return "#<" .. self.name .. ": " .. attr_to_string(data) .. ">"
end

return {
  tostr = tostr
}
