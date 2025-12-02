#!/usr/bin/env bash
set -e

# This module/function must match the Release module we wrote above
./bin/mr_munch_me_accounting_app eval "MrMunchMeAccountingApp.Release.migrate()"