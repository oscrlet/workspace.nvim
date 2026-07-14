local M = {}

local log_path = vim.fn.expand("~/.cache/nvim/workspace.log")
local log_level_map = {
  ERROR = 0,
  WARN = 1,
  INFO = 2,
  DEBUG = 3,
}

local current_level = log_level_map.WARN

local function ensure_log_dir()
  local dir = vim.fn.fnamemodify(log_path, ":h")
  vim.fn.mkdir(dir, "p")
end

local function log(level, msg)
  if log_level_map[level] > current_level then
    return
  end

  ensure_log_dir()

  local timestamp = os.date("%Y-%m-%d %H:%M:%S")
  local log_msg = string.format("[%s] %s: %s", timestamp, level, msg)

  vim.notify(msg, log_level_map[level])

  local f = io.open(log_path, "a")
  if f then
    f:write(log_msg .. "\n")
    f:close()
  end
end

function M.set_level(level)
  if log_level_map[level] then
    current_level = log_level_map[level]
  end
end

function M.error(msg)
  log("ERROR", msg)
end

function M.warn(msg)
  log("WARN", msg)
end

function M.info(msg)
  log("INFO", msg)
end

function M.debug(msg)
  log("DEBUG", msg)
end

return M
