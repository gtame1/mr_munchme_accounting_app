#!/usr/bin/env bash
set -e

# This module/function must match the Release module we wrote above
./bin/ledgr eval "Ledgr.Release.migrate()"