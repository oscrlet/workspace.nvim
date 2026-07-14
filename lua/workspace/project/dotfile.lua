--- workspace/project/dotfile.lua
--- Read/write the on-disk `.project` marker file (JSON).
---
--- Shape (version 1):
---   { "version": 1, "id": string, "name": string,
---     "created_at": number, "meta": table }
---
--- `read(dir)`  -> table | nil       (nil = absent / unreadable / invalid)
--- `write(dir, data)` -> ok, err     (data.id is required)
--- `path(dir)`  -> "<dir>/.project"
local M = {}

M.FILENAME = ".project"
M.VERSION  = 1

---@param dir string
---@return string
function M.path(dir)
  return (dir:gsub("/+$", "")) .. "/" .. M.FILENAME
end

---@param dir string
---@return table|nil
function M.read(dir)
  local file = M.path(dir)
  local stat = vim.uv and vim.uv.fs_stat and vim.uv.fs_stat(file) or nil
  if not stat or stat.type ~= "file" then return nil end
  local ok_lines, lines = pcall(vim.fn.readfile, file)
  if not ok_lines or type(lines) ~= "table" then return nil end
  local raw = table.concat(lines, "\n")
  if raw == "" then return nil end
  local ok_json, decoded = pcall(vim.json.decode, raw)
  if not ok_json or type(decoded) ~= "table" then return nil end
  return decoded
end

---@param dir string
---@param data { id: string, name?: string, meta?: table, created_at?: number }
---@return boolean ok
---@return string|nil err
function M.write(dir, data)
  if type(dir) ~= "string" or dir == "" then
    return false, "dotfile.write: dir must be a non-empty string"
  end
  if type(data) ~= "table" or type(data.id) ~= "string" or data.id == "" then
    return false, "dotfile.write: data.id required"
  end
  local payload = {
    version    = M.VERSION,
    id         = data.id,
    name       = data.name or data.id,
    created_at = data.created_at or os.time(),
    meta       = data.meta or vim.empty_dict(),
  }
  local text = vim.json.encode(payload)
  -- Pretty-print: only top-level keys (closed schema). Keeps the file
  -- hand-editable without dragging in a full JSON formatter.
  text = string.format(
    '{\n  "version": %d,\n  "id": %s,\n  "name": %s,\n  "created_at": %d,\n  "meta": %s\n}',
    payload.version,
    vim.json.encode(payload.id),
    vim.json.encode(payload.name),
    payload.created_at,
    vim.json.encode(payload.meta)
  )
  local ok, err = pcall(vim.fn.writefile, vim.split(text, "\n", { plain = true }), M.path(dir))
  if not ok then return false, tostring(err) end
  return true, nil
end

return M
