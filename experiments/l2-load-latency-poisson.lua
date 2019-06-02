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
    parser:argument("txDev", "Device to transmit from."):convert(tonumber)
    parser:argument("rxDev", "Device to receive from."):convert(tonumber)
    parser:option("-r --rate", "Transmit rate in mp/s."):default("1"):convert(tonumber)
    parser:option("-t --timeLimit", "Time limit in seconds."):default("10"):convert(tonumber)
end

function master(args)
    local txDev = device.config({port = args.txDev, rxQueues = 1, txQueues = 1})
    local rxDev = device.config({port = args.rxDev, rxQueues = 1, txQueues = 1})
    device.waitForLinks()
    -- txDev:getTxQueue(0):setRate(args.rate * (PKT_SIZE + 4) * 8)
    mg.startTask("loadSlave", txDev, rxDev, txDev:getTxQueue(0), args.rate, PKT_SIZE, args.timeLimit)
    -- stats.startStatsTask{txDev, rxDev}
    mg.waitForTasks()
end

function loadSlave(txDev, rxDev, queue, rate, size, timeLimit)
    local mem = memory.createMemPool(function(buf)
        buf:getEthernetPacket():fill{
            ethSrc = txDev,
            ethDst = ETH_DST,
            ethType = 0x1234
        }
    end)
    local bufs = mem:bufArray()
    local rxStats = stats:newDevRxCounter(rxDev, "plain")
    local txStats = stats:newManualTxCounter(txDev, "plain")
    local timeLimit = timer:new(timeLimit)
    local seq = 1
    while mg.running() and not timeLimit:expired() do
        bufs:alloc(PKT_SIZE)
        for i, buf in ipairs(bufs) do
            local pkt = buf:getUdpPacket()
            pkt.payload.uint64[1] = seq
            seq = seq + 1
        end
        for _, buf in ipairs(bufs) do
            -- this script uses Mpps instead of Mbit (like the other scripts)
            buf:setDelay(poissonDelay(10^10 / 8 / (rate * 10^6) - size - 24))
            --buf:setRate(rate)
        end
        txStats:updateWithSize(queue:sendWithDelay(bufs), size)
        rxStats:update()
    end
    rxStats:finalize()
    txStats:finalize()
    queue:stop()
    mg:stop()
end