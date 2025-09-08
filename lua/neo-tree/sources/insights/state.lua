-- lua/neo-tree/sources/uproject/state.lua

local M = {}

local last_request = nil

---
-- 最後に使われたリクエストを保存する
-- @param request table { project_root, engine_root, all_depth, target_module }
function M.set_last_request(request)
  last_request = request
end

---
-- 最後に使われたリクエストを取得する
-- @return table|nil
function M.get_last_request()
  return last_request
end

return M
