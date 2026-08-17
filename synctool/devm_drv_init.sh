#!/bin/bash

# Load log module
source /usr/local/scripts/devm_log_print.sh
# init log
init_log_path "/var/plog" "devm_scripts_run.log"

echo  start the platform init!

chmod 550 /usr/local/scripts/upgrade_drv.sh
/usr/local/scripts/upgrade_drv.sh -s

/usr/local/Ascend/driver/tools/upgrade-tool --clean_upgrade_status

chmod 550  /usr/local/scripts/*
chmod 500  /usr/local/scripts/dump_memory_log.sh
chmod 500  /usr/local/scripts/reboot_log_back_up_check.sh

echo  finish the platform init!
