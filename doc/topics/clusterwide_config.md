# ClusterWideConfig
Clusterwide configuration is more than just a lua table. It's an
object in terms of OOP paradigm.

In Lua it's represented as an object which holds both plaintext files
content and unmarshalled lua tables. Unmarshalling is implicit and
performed automatically for the sections with `.yml` file extension.

To access plaintext content there are two functions: `get_plaintext`
and `set_plaintext`.

Unmarshalled lua tables are accessed without `.yml` extension by
`get_readonly` and `get_deepcopy`. Plaintext serves for
accessing unmarshalled representation of corresponding sections.

To avoid ambiguity it's prohibited to keep both `<FILENAME>` and
`<FILENAME>.yml` in the configuration. An attempt to do so would
result in `return nil, err` from `new()` and `load()`, and an attempt
to call `get_readonly/deepcopy` would raise an error.
Nevertheless one can keep any other extensions because they aren't
unmarshalled implicitly.

```
tarantool> cfg = ClusterwideConfig.new({
         >     -- two files
         >     ['forex.yml'] = '{EURRUB_TOM: 70.33, USDRUB_TOM: 63.18}',
         >     ['text'] = 'Lorem ipsum dolor sit amet',
         > })
...

tarantool> cfg:get_plaintext()
---
- text: Lorem ipsum dolor sit amet
  forex.yml: '{EURRUB_TOM: 70.33, USDRUB_TOM: 63.18}'
...

tarantool> cfg:get_readonly()
---
- forex.yml: '{EURRUB_TOM: 70.33, USDRUB_TOM: 63.18}'
  forex:
    EURRUB_TOM: 70.33
    USDRUB_TOM: 63.18
  text: Lorem ipsum dolor sit amet
...
```

For example add to previous config nested files:

```
tarantool> cfg:set_plaintext('files/file1', 'file1')
tarantool> cfg:set_plaintext('files/file2', 'file2')
```

And config represents as following structure:
```
---
- _plaintext:
    files/file2: file2
    forex.yml: '{EURRUB_TOM: 70.33, USDRUB_TOM: 63.18}'
    files/file1: file1
    text: Lorem ipsum dolor sit amet
  locked: false
  _luatables:
    files/file2: file2
    forex:
      EURRUB_TOM: 70.33
      USDRUB_TOM: 63.18
    files/file1: file1
    forex.yml: '{EURRUB_TOM: 70.33, USDRUB_TOM: 63.18}'
    text: Lorem ipsum dolor sit amet
...
```

On filesystem clusterwide config is represented by a file tree.
As you see, ClusterwideConfig support nested folders, you need to add
section with path_delimiter `/`. Previous config on filesystem looks like this:
```
|- config_dir
            |- forex.yml
            |- text
            |- files
                |- file1
                |- file2
```

# Clusterwide config managment

## Twophase
There is no need to create config manually, because managing config lifecycle
is a part of `twophase` module. This module is a clusterwide configuration
propagation two-phase algorithm. Main function of this module is a
`private` function `_clusterwide(patch)` which accepts `config patch` and
creates new `config` by merging old one with current `patch`. After config
creation, instance where `_clusterwide` was called, initiates `twophase commit`
for applying this config on cluster instances by `pool.map_call` (map-reduce).

There are three stages at twohphase algorithm:
- Prepare stage:
  From this stage we can go to `Commit` stage if there was no errors and to `Abort` stage
  if error occures at some instances during `map_call`.
  So if error occures at this stage config won't be applied on cluster instances
  (rollbacks to previous config - `config.backup`)

- Commit stage:
  This stage is final.
  If there was no error - config applied.
  But if error occures at this stage on some instances, then this cluster instances
  will be at unconsistent state and there is no way exept manually instances recover.

- Abort stage:
  This stage is final. 
  Abort config changes on instances and rollbacks to previous config.

`Twophase` module has `public` wrapper for `_clusterwide` - function `thwophase.patch_clusterwide(patch)`,
also `patch_clusterwide` is a part of public `cartridge` API named `cartridge.config_patch_clusterwide`

# Applying config API

API for apply new config:
- Lua
- Luatest
- Http
- Graphql

## Lua and Luatest API

### Lua API
- `cartridge.config_patch_clusterwide(patch)` - apply config patch
  
- `cartridge.config_get_deepcopy(section_name)`
  @tparam[opt] string section_name
  @treturn table
  If key is nil then returns all config data (_plaintext - yaml encoed data and unmarshalled data)
  also here we can see cartridge.system_sections (topology, vshard, users_acl, auth)

- `cartridge.config_get_readonly(section_name)`
  same as get_deepcopy, but data can't be modified

```lua
localhost:3301> cartridge.config_patch_clusterwide({['data.yml'] = '---\ndata: 5\n...'})
---
- true
...

localhost:3301> cartridge.config_get_readonly('data.yml')
---
- '---

  data: 5

  ...'
...

localhost:3301> cartridge.config_get_readonly('data')
---
- data: 5
...

-- Same for config.get_deepcopy()
```

There are also many API endpoints that implicitly calls `twophase.patch_clusterwide()`
Some of them:
- Auth: `auth.set_params()`
- Users acl: `add_user`/`edit_user`/`remove_user`
- Topology: `edit_topology` (and deprecated `edit_server`/`expel_server`/`join_server`/`edit_replicaset`)
- Vshard utils edit_vshard_options; admin_bootstrap_vshard
- Failover set_params(opts) / lua_api_failover set_failover params() graphql
- api_ddl
- api_config

### Luatest API

`cartridge.test_helpers.server` extends basic `luatest.server` with some useful methods, one of
them is `upload_config` - it's a wrapper over `HTTP PUT /admin/config`.

```lua
-- @tparam string|table config - table will be encoded as yaml and posted to /admin/config.
function Server:upload_config(config)
    ...
end
```

Also `cartridge.test_helpers.cluster` has the same method for uploading config
(it's a shortcut for `cluster.main_server:upload_config(config)`).

```lua
function Cluster:upload_config(config)
    ...
end
```

Example of use:

```lua
-- create cluster
g.before_all = function()
  g.cluster = helpers.Cluster.new(...)
end

... 

local custom_config = {
  ['custom_config'] = {
      ['Ultimate Question of Life, the Universe, and Everything'] = 42
  }
}
g.cluster:upload_config(custom_config)
```

## HTTP and graphql API

Both graphql API and HTTP API don't quering cluster following sections (named `system_sections`)
- auth, auth.yml,
- topology, topology.yml
- users_acl, users_acl.yml
- vshard, vshard.yml,
- vshard_groups, vshard_groups.yml,

Sections has duplicates with/without `.yml` extension, because new ClusterwideConfig works with
`.yml` extension and sections without extension we have to save for backward compatibility.

This sections can't be modified by raw update/download config, because for modifying this sections
`cartridge` have separate API with additional validation checks.
Some of them:
- Auth: `add_user`/`edit_user`/`remove_user`
- Topology: `edit_topology` (and deprecated `edit_server`/`expel_server`/`join_server`/`edit_replicaset`) and failover gql endoints
- Vshard:
- Api ddl


## Graphql API

### Graphql types

```graphql
"""A section of clusterwide configuration"""
type ConfigSection {
  filename: String!
  content: String!
}

"""A section of clusterwide configuration"""
input ConfigSectionInput {
  filename: String!
  content: String
}
```

### Quering config sections:

```graphql
"""Applies updated config on cluster"""
mutation {
  cluster {
    config(sections: [ConfigSectionInput]): [ConfigSection]!
  }
}

"""Get cluster config sections"""
query {
  cluster {
    config(sections: [String!]): [ConfigSection]!
  }
}
```

### Examples

Add example quering and settign, also may be show system section
```graphql
query {
  cluster {
    config {
      sections({{
        
      }})
    }
  }
}
```

## HTTP API

Currently supported only uploading/downloading yaml config.

### Upload config:

`HTTP PUT /admin/config`

### Download config:

`HTTP GET /admin/config`

### Examples
Show an examples with curl 

