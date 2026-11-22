; version.inc - Horizon's version, the one place it is set (the kernel's boot banner,
; About, ...). Included by kernel/kdefs.inc and user/horizon.inc.
.define HORIZON_VERSION "0.29"
; (0.29) the same as numbers: sys_info ($36) returns HORIZON_MAJOR << 8 | HORIZON_MINOR
HORIZON_MAJOR = 0
HORIZON_MINOR = 29
