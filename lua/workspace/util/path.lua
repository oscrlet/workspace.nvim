local M = {}

function M.expand(p)
  return vim.fn.expand(p)
end

function M.realpath(p)
  local expanded = M.expand(p)
  local ok, result = pcall(vim.uv.fs_realpath, expanded)
  if ok and result then
    return result
  end
  return M.expand(expanded)
end

function M.data_dir()
  -- Honor user-configurable cfg.data_dir when available.
  -- pcall-guard the require: during early init the config module may not
  -- yet be merged (or may even fail to load), in which case we fall back
  -- to the historical stdpath-based default.
  local ok, cfg_mod = pcall(require, "workspace.config")
  if ok and cfg_mod and cfg_mod.get then
    local cfg = cfg_mod.get()
    if cfg and cfg.data_dir and cfg.data_dir ~= "" then
      return cfg.data_dir
    end
  end
  local sp_ok, sp = pcall(vim.fn.stdpath, "data")
  if sp_ok and sp and sp ~= "" then
    return sp .. "/workspace"
  end
  return M.expand("~/.local/share/nvim/workspace")
end

function M.ensure_dir(p)
  vim.fn.mkdir(p, "p")
end

return M
