NAME := wc
SDK  ?= ../../..
ARGS := /WCTEST.TXT /NOSUCH.TXT /WCTEST.TXT
RUNFLAGS := --file test.txt:/WCTEST.TXT --seconds 3
TESTFLAGS := --expect '       3       9      46 /WCTEST.TXT' \
             --expect 'wc: /NOSUCH.TXT: No such file or directory' \
             --expect '       6      18      92 total'
include $(SDK)/c/c.mk
