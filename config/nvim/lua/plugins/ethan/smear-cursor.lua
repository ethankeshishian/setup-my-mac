return {
  "sphamba/smear-cursor.nvim",
  lazy = false,
  opts = {                                -- Default  Range
    stiffness = 0.9,                      -- 0.6      [0, 1] - Higher = faster/snappier
    trailing_stiffness = 0.7,             -- 0.4      [0, 1] - Higher = less trailing
    stiffness_insert_mode = 0.9,          -- 0.5      [0, 1] - Higher = faster
    trailing_stiffness_insert_mode = 0.8, -- 0.5      [0, 1] - Higher = less trailing
    damping = 0.9,                        -- 0.65     [0, 1] - Higher = less oscillation
    damping_insert_mode = 0.9,            -- 0.7      [0, 1] - Higher = less oscillation
    distance_stop_animating = 0.3,        -- 0.1      > 0   - Lower = stops sooner
  },
}
