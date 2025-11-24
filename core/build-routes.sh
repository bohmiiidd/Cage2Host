#!/usr/bin/env bash

########################################
# MAIN SCRIPT TO BUILD routes.conf
########################################
source core/utils.sh
reset_routes_conf
scan_autoScripts
scan_modules
scan_exploits
