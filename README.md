# Sohm

Slimmed ohm for twemproxy-like Redis cluster

# Description

While the original [ohm](https://github.com/soveran/ohm) is a beautifully crafted library with almost all features you would expect when using Redis as a database, it has one small disadvantage: it requires a full featured Redis implementation, and will not work on a Redis proxy cluster such as [twemproxy](https://github.com/twitter/twemproxy) or [codis](https://github.com/wandoulabs/codis). Depending on your requirements, this might or might not be a problem.

Instead of an improvement over ohm, we consider sohm as an alternative to ohm: when you are okay with a limited feature set of Redis, using sohm together with twemproxy/codis can give you a backend that is much easier to scale.

That being said, we still want to warn you that in some cases, sohm might be too limited for your applications, and the original ohm might be much better.

# Why Use Lua?

These days I'm having this impressions: most dynamic languages(such as Ruby, Python, Scala, Clojure, Lua, Erlang/Elixir, etc.) share basically the same feature set: each one has OO implementations with open classes, first class function support, as well as some sort of meta-programming techniques. There're people supporting each language and believing that their language of choice is beautiful. To me, this is really a matter of personal taste and culture difference.

On the other hand, modern Web applications continue to be slow: not that web applications are not scalable, but that efforts are needed to make applications performant. I'm quite confident that we've all been there: we started with a plain Web application written in language of our choice, the application also talks to a plain SQL database(could be either MySQL or PostgreSQL). All of a sudden, the application gains attraction, and more people are using it than our servers can handle. We have to work overtime here to add more servers, shard the databases, include cache layers. In the meantime, it might or might not be possible to make the code still in a readable state. In certain cases, the application would result in a messy state that is hard to maintain. On the one hand, we keep saying that premature optimization is the root of all evils, on the other hand, it usually takes a lot of efforts to make servers Web scale.

That leaves me to wonder this question: what can we do in advance to make sure our Web application is scalable? Note we are never saying that current techniques are not enough, the problem is really to reduce the efforts needed to improve performance. By leveraging tools, we believe we can keep our focus on the feature development for a considerably long period of time, hence making it less likely that our application reaches a messy state.

After some research, I'd like to spend some time with [OpenResty](https://openresty.org/), which is a Web application server enabled by bundling LuaJIT with nginx. LuaJIT is one of the fastest dynamic language implementations out there, combining with nginx's non-blocking feature, we can have a real performant server that works in a non-blocking way while you are writing blocking synchronous Lua code.

One thing that interests me, is that the author of OpenResty actually planned to build a solution for full stack Web application, however, somehow OpenResty ends up more used in CDN or WAF world. With sohm as well as a few other projects, I'm trying to contribute to a stack that Lua is used to build full stack Web application, the result of which can be a real performant server where developers can mostly focus on feature development.

So what will you do if I give you something that is much less of a concern when traffic increases, but might not be your favorite language(while providing productivity on par with your choice)?

# But V8 and JVM can be as fast as LuaJIT, or even faster!

I'm not saying that here LuaJIT is the fastest, there're a few equally performant(by equally performant, I mean they live in the same order of magnitude in performance) choices here:

* Scala/Clojure: JVM is a real performance beast, Scala or Clojure can also provide the dynamic features we need to craft beautiful Web application code(despite that Scala is static typed!). However, to achieve the same level of performance, JVM usually consumes much more memory and requires careful tuning, which might not fit everyone.
* Node.js: V8 is awesome, in some benchmarks V8 is even faster than LuaJIT, so we cannot ignore this choice. However, even with promises you still have to deal with the asynchronous behavior of JavaScript, where OpenResty allows you to write synchronous code which are running aynchronously underneath.

It is very likely that another developer might come to a very different conclution than I do. Here I just want to emphasize on the following points:

* With the architecture enabled by sohm as well as corresponding projects, it is possible to build a performant architecture that is not sacrificing much productivity.
* There're also other(tho very limited, and chances are your favorite language does not belong here) language choices for making a similar performant architecture, LuaJIT is just my choice, and I hope that will also be your choice :)

That being said, it is also possible that you still believe the bottleneck of Web applications is IO, and you don't think I'm right to use OpenResty, I still maintain a Ruby version of sohm you can check out at [here](https://github.com/xxuejie/sohm).

# Getting Started

First you need to have [Redis](http://redis.io/) installed and running on your system, or you can also have a Redis hosted instance running somewhere.

Next, you should have [Redic.lua](https://github.com/xxuejie/redic.lua) in your Lua package path. We might setup some packaging solution in the future(such as Luarocks), however, we are waiting for the packaging solution for OpenResty to be available now, so we don't have anything ready yet. Please stay tuned for this.

You should also have [lua-MessagePack](https://github.com/fperrad/lua-MessagePack/) installed, which will be used to serialize attributes.

Now you can grab sohm.lua code at <https://github.com/xxuejie/sohm.lua>. Suppose the code is stored at /foo/bar/sohm, you need to make sure Lua package path contains `/foo/bar/sohm/?.lua` in order to make sohm work.

One tip I'm personally now using, is that you can group your Lua libraries in the following path:

```
/foo/bar/libs/sohm
/foo/bar/libs/redic
```

All you need to do then, is to add `/foo/bar/libs/?.lua;/foo/bar/libs/?/?.lua` to the package path, and everything will be working just fine.

# Connection to Redis

Sohm.lua uses [Redic.lua](https://github.com/xxuejie/redic.lua) to communicate with Redis. As a result, sohm.lua does not need to care what underlying Redis backend we are using, which could be [lua-resty-redis](https://github.com/openresty/lua-resty-redis), [resp](https://github.com/soveran/resp) or [redis-lua](https://github.com/nrk/redis-lua).

Using lua-resty-redis as an example, we can setup Redic.lua like this:

```lua
local redis = require "resty.redis"
local red = redis:new()

red:set_timeout(1000) -- 1 sec

-- or connect to a unix domain socket file listened
-- by a redis server:
--     local ok, err = red:connect("unix:/path/to/redis.sock")

local ok, err = red:connect("127.0.0.1", 6379)
if not ok then
    ngx.say("failed to connect: ", err)
    return
end

local redic = require "redic"
local db = redic(red, "lua-resty-redis")
```

Now we can use `db` in sohm.lua.

# Models

We can define sohm models like this:

```lua
local sohm = require "sohm"
local msgpack = require "messagepack"

return sohm.model("User", {
  attributes = {
    "lname",
    "fname"
  },

  serial_attributes = {
    "email"
  }
}, msgpack)
```

Suppose the above model is stored in `user.lua` in the package path. We can now use it:

```lua
local user = require("user")

local data = {
  id    = 1,
  fname = "John",
  lname = "Doe",
  email = "john@example.org"
}

user:save(db, data, {cas = true})
```

If you are familiar with ohm, you will recognize several differences:

1. ID is a required field in sohm, we will not generate an ID by default in sohm.
2. In addition to normal attributes, we also support serial attributes that are set in a CAS way: suppose you fetch a model from database, then someone else modifies the same model, you will not be able to save the model unless you fetch it from the database again. This can be used to guard certain critical data.
3. The core sohm has no index support. You can only query a model by ID here, later we will see that index is supported via a plugin, i.e., index will only be available when you explicitly say so.
4. Sohm has no support for multiple unique indices. The only unique index available is the model ID. As a result, model ID can be any string, it is not necessarily the fact that model ID is a number.
5. Sohm preserves types: if an attribute is a number, it will always be a number when we save it and refetch the model again. You can store arrays or maps in the attributes as well: as long as MessagePack can serialize/deserialize the data, they will be preserved. The only exception here is ID, which is always treated as a string.

Notice the CAS option is off by default: if you model does not use serial attributes, or you are sure the serial attributes are not modified, you can use a fast path here:

```lua
user:save(db, data)
```

Some model might not need to be persisted at all times, so you can also add an expiration time to a model:

```lua
-- Model is valid for an hour
user:save(db, data, {expire = 3600})
```

Sohm is designed with performance in mind, you will not pay the cost if you are not using any additional feature. One example here is: if we are not using indices, CAS or expiration, the core sohm can save a model via a single Redis `HMSET` command. This is the fastest path I can think of right now.

You can fetch a model from Redis via ID:

```lua
local data, err = user:fetch(db, "1")
```

You can delete an existing model either via ID or model data:

```lua
local data, err = user:fetch(db, "1")
user:delete(db, data)

-- Or you can also use ID directly
user:delete(db, "1")
```

Counter is also working in sohm, suppose the user model is changed to this:

```lua
local sohm = require "sohm"
local msgpack = require "messagepack"

return sohm.model("User", {
  attributes = {
    "lname",
    "fname"
  },

  serial_attributes = {
    "email"
  },

  counters = {
    "votes"
  }
}, msgpack)
```

You can read, increase or decrease a counter:

```lua
local data = user:fetch(db, "1")
local votes = user:votes(db, data)

-- Or you can use ID as well
votes = user:votes(db, "1")

-- Increase a vote:
user:incr(db, "1", "votes", 2)

-- And decrease one:
user:incr(db, data, "votes", 3)
```

# Set & List

`set` and `list` are also supported in sohm:

```lua
local address_model = sohm.model("Address", {
  attributes = {
    "line",
    "city",
    "zipcode"
  }
}, msgpack)

local user_model sohm.model("User", {
  attributes = {
    "lname",
    "fname"
  },

  serial_attributes = {
    "email"
  },

  sets = {
    "address_set"
  },

  lists = {
    "address_list"
  }
}, msgpack)

-- For simplicity, let's assume we have a few addresses saved to the database:
local address1 = address_model:fetch(db, "1")
local address2 = address_model:fetch(db, "2")

-- Add them to set
local set = user_model:address_set(db, address_model)
set:add(db, "1")
set:add(db, address2)

-- Delete from set
set:delete(db, address1)

-- Test existence
if set:exists(db, "2") then print("Address 2 exists in set!") end

-- Fetch from set
local address_to_fetch = set:fetch(db, "1")

-- Get IDs
local ids = set:ids(db)

-- Get Size
local size = set:size(db)

-- Get an iterator of set items
for addr in set:iter(db) do
  -- Do something with addr
end

-- List works in a similar way
local list = user_model:address_list(db, address_model)

list:push(db, "1")
list:unshift(db, address2)

local first_item = list:first(db)
local last_item = list:last(db)

for addr in list:range(db, 0, -1) do
  -- Do something with addr
end

-- Remove the first one
list:shift(db)

-- Remove the last one
list:pop(db)

-- Delete an item from the whole list
list:delete(db, "3")
```

# Plugins

Core sohm only includes limited features that will not affect performance. We also have a few plugins you can use according to your needs:

## AutoId

In case you don't care what ID is used for the model, you can include this plugin to automatically generate a numeric ID for you, just like what ohm does:

```lua
local sohm_auto_id = require("sohm.auto_id")
local address_model = sohm.model("Address", {
  attributes = {
    "line",
    "city",
    "zipcode"
  },
  plugins = {
    sohm_auto_id
  }
}, msgpack)

local address_data = { line = "Main Street 1", city = "New York",
                       zipcode = 10001 }
-- You can save the data here without an ID
address_model:save(db, address_data)
```

## ToStr

This plugin can print a nice representation of the model:

```lua
local sohm_tostr = require("sohm.tostr")
local address_model = sohm.model("Address", {
  attributes = {
    "line",
    "city",
    "zipcode"
  },
  plugins = {
    sohm_tostr
  }
}, msgpack)

local data = address_model:fetch(db, "1")
address_model:tostr(db, data)
```

Notice we didn't use `__tostring` on purpose, since `data` is just a table, we don't want to override table's `__tostring` which might break other code.

## Index

Index is provided here as a plugin:

```lua
local sohm_auto_id = require("sohm.auto_id")
local sohm_index = require("sohm.index")
local address_model = sohm.model("Address", {
  attributes = {
    "line",
    "city",
    "zipcode"
  },
  indices = {
    "zipcode"
  },
  plugins = {
    sohm_auto_id,
    sohm_index
  }
}, msgpack)

local address_data = { line = "Main Street 1", city = "New York",
                       zipcode = 10001 }
address_model:save(db, address_data)

-- Use refresh to manually update indices
address_model:refresh(db, address_data)

-- Now you can query on the index
local set = address_model:find(db, "zipcode", 10001)

-- set here is just a normal set as shown above, the only difference is
-- that this set is not mutable
for addr in set:iter(db) do
  -- Use addr
end
```

When index is enabled, `reference` and `collection` works as well:

```lua
local sohm_auto_id = require("sohm.auto_id")
local sohm_index = require("sohm.index")
local address_model = sohm.model("Address", {
  attributes = {
    "line",
    "city",
    "zipcode"
  },

  references = {
    "user_id"
  },

  indices = {
    "zipcode"
  },

  plugins = {
    sohm_auto_id,
    sohm_index
  }
}, msgpack)

local user_model sohm.model("User", {
  attributes = {
    "lname",
    "fname"
  },

  serial_attributes = {
    "email"
  },

  collections = {
    "addresses"
  },

  plugins = {
    sohm_auto_id,
    sohm_index
  }
}, msgpack)

local address_data = { line = "Main Street 1", city = "New York",
                       zipcode = 10001, user_id = "1" }
address_model:save(db, address_data)

local user = address_model:user(db, address_data, user_model)

for addr in user_model:addresses(db, user, address_model):iter(db) do
  -- Use addr
end
```

## IndexAll

When index is enabled, another plugin `IndexAll` can give you the original `all` in Sohm:

```lua
local sohm_auto_id = require("sohm.auto_id")
local sohm_index = require("sohm.index")
local sohm_index_all = require("sohm.index_all")
local address_model = sohm.model("Address", {
  attributes = {
    "line",
    "city",
    "zipcode"
  },
  indices = {
    "zipcode"
  },
  plugins = {
    sohm_auto_id,
    sohm_index,
    sohm_index_all
  }
}, msgpack)

for addr in address_model:all(db) do
  -- Use addr here
end
```
