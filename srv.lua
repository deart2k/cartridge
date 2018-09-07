#!/usr/bin/env tarantool

require('strict').on()
local fio = require('fio')
local log = require('log')
local term = require('term')
local errors = require('errors')
local console = require('console')
local cluster = require('cluster')

local init_error = errors.new_class('Cluster initialization failed')
local ok, err = init_error:pcall(cluster.init, {
    workdir = os.getenv('WORKDIR') or './dev/output',
    advertise_uri = os.getenv('ADVERTISE_URI') or 'localhost:3301',
})

if not ok then
    log.error('%s', err)
    os.exit(1)
end

if term.isatty(io.stdout) then
    _G.cluster = cluster
    console.start()
    os.exit(0)
end
