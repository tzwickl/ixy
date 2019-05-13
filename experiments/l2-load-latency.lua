local mg     = require "moongen"
local memory = require "memory"
local device = require "device"
local ts     = require "timestamping"
local stats  = require "stats"
local timer  = require "timer"

local PKT_SIZE	= 60
local ETH_DST	= "11:12:13:14:15:16"

local function getRstFile(...)
    local args = { ... }
    for i, v in ipairs(args) do
        result, count = string.gsub(v, "%-%-result%=", "")
        if (count == 1) then
            return i, result
        end
    end
    return nil, nil
end

function configure(parser)
    parser:description("Generates directional CBR traffic with hardware rate control and measure latencies.")
    parser:argument("dev1", "Device to transmit from."):convert(tonumber)
    parser:argument("dev2", "Device to receive from."):convert(tonumber)
    parser:option("-r --rate", "Transmit rate in mp/s."):default("1"):convert(tonumber)
    parser:option("-t --timeLimit", "Time limit in seconds."):default("10"):convert(tonumber)
end

function master(args)
    local dev1 = device.config({port = args.dev1, rxQueues = 1, txQueues = 1})
    local dev2 = device.config({port = args.dev2, rxQueues = 1, txQueues = 1})
    device.waitForLinks()
    dev1:getTxQueue(0):setRate(args.rate * (PKT_SIZE + 4) * 8)
    mg.startTask("loadSlave", dev1:getTxQueue(0), args.timeLimit)
    stats.startStatsTask{dev1, dev2}
    mg.waitForTasks()
end

function loadSlave(queue, timeLimit)
    local mem = memory.createMemPool(function(buf)
        buf:getEthernetPacket():fill{
            ethSrc = txDev,
            ethDst = ETH_DST,
            ethType = 0x1234
        }
    end)
    local bufs = mem:bufArray()
    local timeLimit = timer:new(timeLimit)
    while mg.running() and not timeLimit:expired() do
        bufs:alloc(PKT_SIZE)
        queue:send(bufs)
    end
    queue:stop()
    mg:stop()
end