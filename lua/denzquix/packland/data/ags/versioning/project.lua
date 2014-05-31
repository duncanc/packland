
local versioning = require 'denzquix.packland.versioning'

local v = versioning.schema 'game file format'

v.v_LotD = v(9) -- Lunchtime of the Damned

v.v2_3_0 = v(12)
v.v2_4_0 = v2_3_0
v.v2_5_0 = v(18)
v.v2_5_1 = v(19)
v.v2_5_2 = v2_5_1
v.v2_5_3 = v(20)
v.v2_5_4 = v(21)
v.v2_5_5 = v(22)
v.v2_5_6 = v(24)
v.v2_6_0 = v(25)
v.v2_6_1 = v(26)
v.v2_6_2 = v(27)
v.v2_7_0 = v(31)
v.v2_7_2 = v(32)
v.v3_0_0 = v(35)
v.v3_0_1 = v(36)
v.v3_1_0 = v(37)
v.v3_1_1 = v(39)
v.v3_1_2 = v(40)
v.v3_2_0 = v(41)
v.v3_2_1 = v(42)
v.v3_3_0 = v(43)

v.v_current = v3_3_0

return v
