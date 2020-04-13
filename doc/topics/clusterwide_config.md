Clusterwide configuration is more than just a lua table. It's an
object in terms of OOP paradigm.

On filesystem clusterwide config is represented by a file tree.
Example config:
```
workdir
      |- instance
                |- config
                        |- auth.yml
                        |- vshard.yml
                        |- topology.yml
                        |- text
                        |- some_data.yml
                        |- files
                               |- file1
                               |- file2
```

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

Simpliest way to apply new config on cluster it's call `cartridge.config_patch_clusterwide(...)`
(it's an alias to `twophase.patch_clusterwide`). Instance that iniciates applying new patch creates
new `ClusterwideConfig`, right after config has been created, instance initiates `twophase commit` on
cluster instances, by `pool.map_call` (map-reduce). If `error` occures on some cluster instances during
`twophase commit preparation stage` then config won't be applied (rollbacks to `config.backup`). If error
occures at `commit stage`, then some instances at cluster will be at unconsistent state and there
is no way exept manually instances recover.

There are many API endpoints that implicitly calls `twophase.patch_clusterwide()`:
