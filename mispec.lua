local moduleName = ...
local M = {}
_G[moduleName] = M

-- Helpers:
function ok(expression, desc)
    if expression == nil then expression = true end
    desc = desc or 'expression is not ok'
    if not expression then
        error(desc .. '\n' .. debug.traceback())
    end
end

function ko(expression, desc)
    if expression == nil then expression = true end
    desc = desc or 'expression is not ko'
    if expression then
        error(desc .. '\n' .. debug.traceback())
    end
end

function eq(a, b)
    if type(a) ~= type(b) then
        error('type ' .. type(a) .. ' is not equal to ' .. type(b))
    end
    if type(a) == 'function' then
        return string.dump(a) == string.dump(b)
    end
    if a == b then return true end
    if type(a) ~= 'table' then
        error(a .. ' is not equal to ' .. b)
    end
    for k,v in pairs(a) do
        if b[k] == nil or not eq(v, b[k]) then return false end
    end
    for k,v in pairs(b) do
        if a[k] == nil or not eq(v, a[k]) then return false end
    end
    return true
end

local function eventuallyImpl(func, retries, delayMs)
    local prevEventually = _G.eventually
    _G.eventually = function() error("Can not nest eventually/andThen.") end
    local status, err = pcall(func)
    _G.eventually = prevEventually
    if status then
        M.queuedEventuallyCount = M.queuedEventuallyCount - 1
        M.runNextPending()
    else
        if retries > 0 then
            local t = tmr.create()
            t:register(delayMs, 0, M.runNextPending)
            t:start()

            table.insert(M.pending, 1, function() eventuallyImpl(func, retries - 1, delayMs) end)
        else
            M.failed = M.failed + 1
            print("\n  ' it failed:", err)
            M.queuedEventuallyCount = M.queuedEventuallyCount - 1
            M.runNextPending()
        end
    end
end

function eventually(func, retries, delayMs)
    retries = retries or 10
    delayMs = delayMs or 300

    M.queuedEventuallyCount = M.queuedEventuallyCount + 1

    table.insert(M.pending, M.queuedEventuallyCount, function()
        eventuallyImpl(func, retries, delayMs)
    end)
end

function andThen(func)
    eventually(func, 0, 0)
end

function describe(name, itshoulds)
    M.name = name
    M.itshoulds = itshoulds
end

-- Module:
M.pending = {}
M.queuedEventuallyCount = 0

M.runNextPending = function()
    local next = table.remove(M.pending, 1)
    if next then
        node.task.post(next)
    else
        M.succeeded = M.total - M.failed
        local elapsedSeconds = (tmr.now() - M.startTime) / 1000 / 1000
        print(string.format(
            '\n\nCompleted in %.2f seconds.\nSuccess rate is %.1f%% (%d failed out of %d).',
            elapsedSeconds, 100 * M.succeeded / M.total, M.failed, M.total))
    end
end

M.run = function()
    M.startTime = tmr.now()
    M.total = 0
    M.failed = 0
    local it = {}
    it.should = function(_, desc, func)
        table.insert(M.pending, function()
            uart.write(0, '\n  * ' .. desc)
            M.total = M.total + 1
            local status, err = pcall(func)
            if not status then
                print("\n  ' it failed:", err)
                M.failed = M.failed + 1
            end
            M.runNextPending()
        end)
    end
    M.itshoulds(it)

    print('' .. M.name .. ', it should:')
    M.runNextPending()
end
