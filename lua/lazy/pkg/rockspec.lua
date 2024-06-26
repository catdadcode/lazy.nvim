--# selene:allow(incorrect_standard_library_use)
local Config = require("lazy.core.config")
local Util = require("lazy.util")

local M = {}

M.dev_suffix = "-1.rockspec"
M.skip = { "lua" }

M.rewrites = {
  ["plenary.nvim"] = { "nvim-lua/plenary.nvim", lazy = true },
}

---@param plugin LazyPlugin
function M.deps(plugin)
  local root = Config.options.rocks.root .. "/" .. plugin.name
  local manifest_file = root .. "/lib/luarocks/rocks-5.1/manifest"
  local manifest = {}
  pcall(function()
    local load, err = loadfile(manifest_file, "t", manifest)
    if not load then
      error(err)
    end
    load()
  end)
  return vim.tbl_keys(manifest.repository or {})
end

---@class RockSpec
---@field rockspec_format string
---@field package string
---@field version string
---@field dependencies string[]
---@field build? {build_type?: string, modules?: any[]}

---@param plugin LazyPlugin
---@return LazyPkgSpec?
function M.get(plugin)
  if M.rewrites[plugin.name] then
    return {
      file = "rewrite",
      source = "lazy",
      spec = M.rewrites[plugin.name],
    }
  end

  local rockspec_file ---@type string?
  Util.ls(plugin.dir, function(path, name, t)
    if t == "file" and name:sub(-#M.dev_suffix) == M.dev_suffix then
      rockspec_file = path
      return false
    end
  end)

  if not rockspec_file then
    return
  end

  ---@type RockSpec?
  ---@diagnostic disable-next-line: missing-fields
  local rockspec = {}
  local load, err = loadfile(rockspec_file, "t", rockspec)
  if not load then
    error(err)
  end
  load()

  if not rockspec then
    return
  end

  local has_lua = not not vim.uv.fs_stat(plugin.dir .. "/lua")

  ---@type LazyPluginSpec
  local rewrites = {}

  ---@param dep string
  local rocks = vim.tbl_filter(function(dep)
    local name = dep:gsub("%s.*", "")
    if M.rewrites[name] then
      table.insert(rewrites, M.rewrites[name])
      return false
    end
    return not vim.tbl_contains(M.skip, name)
  end, rockspec.dependencies or {})

  local use = not has_lua
    or #rocks > 0
    or (
      rockspec.build
      and rockspec.build.build_type
      and rockspec.build.build_type ~= "none"
      and not (rockspec.build.build_type == "builtin" and not rockspec.build.modules)
    )

  if not use then
    if #rewrites > 0 then
      return {
        file = vim.fn.fnamemodify(rockspec_file, ":t"),
        spec = rewrites,
      }
    end
    return
  end

  local lazy = nil
  if not has_lua then
    lazy = false
  end

  return {
    file = vim.fn.fnamemodify(rockspec_file, ":t"),
    spec = {
      plugin.name,
      build = "rockspec",
      lazy = lazy,
    },
  }
end

return M
