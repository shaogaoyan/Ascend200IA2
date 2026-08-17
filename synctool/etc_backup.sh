#!/bin/bash

# Load log module
source /usr/local/scripts/devm_log_print.sh
# init log
init_log_path "/var/plog" "devm_scripts_run.log"


backup_base_dir=/home/data/etc
backup_file_list=$(cat /usr/local/scripts/backup_file_list.txt)
account_file_list=$(cat /usr/local/scripts/acount_file_list.txt)
backup_dir_list=$(cat /usr/local/scripts/backup_dir_list.txt)
eth_file_name=/etc/sysconfig/network-scripts/ifcfg-eth

upgrade_backup_file()
{
    target_file=$1
    backup_file=${backup_base_dir}/${target_file#/etc/}
    echo "backup_file is $backup_file"
    #refresh verification for target file!
    sha512sum $target_file > /run/backup_check.sha512
    if [ ! -d "$(dirname ${backup_base_dir}${target_file#/etc})" ];then
        mkdir -p $(dirname ${backup_base_dir}${target_file#/etc})
    fi
    dd if=/run/backup_check.sha512 of=${backup_file}.sha512 conv=fsync status=none
    #upgrade backup file!
    if [ "$target_file" == "/etc/localtime" ] || [ "$target_file" == "/etc/rc.local" ];then
        cp -af $target_file ${backup_base_dir}/
        ln -sf $(realpath "$target_file") ${backup_base_dir}/${target_file#/etc/}
    else
        cp -af $target_file ${backup_file}
    fi

    echo upgrade verify and backup for $target_file
    logger_info "upgrade verify and backup for $target_file"
}

upgrade_account_file()
{
    target_file=$1
    file_list=`cat /usr/local/scripts/acount_backup_file.grp`
    #refresh verification for target file!
    rm -f /run/account_check.sha512
    for i in $file_list
    do
        group_file=$i
        sha512sum "${group_file}" >> /run/account_check.sha512
    done
    dd if=/run/account_check.sha512 of=${backup_base_dir}/account_check.sha512 conv=fsync status=none
    sha512sum ${backup_base_dir}/account_check.sha512 > /run/account_check.vrf
    dd if=/run/account_check.vrf of=${backup_base_dir}/account_check.vrf conv=fsync status=none
    #upgrade backup file
    for i in $file_list
    do
        group_file=$i
        echo "group_file is $group_file"
        cp -af $group_file ${backup_base_dir}/${group_file#/etc/}
    done
    echo upgrade account verify and backup for $target_file
    logger_info "upgrade account verify and backup for $target_file"
}

upgrade_backup_dir_file()
{
    target_file=$1
    backup_file=${backup_base_dir}/${target_file#/etc/}
    if [ "$target_file" != "/etc/modules-load.d/10-atlas-default.conf" ];then
        echo "backup_file is $backup_file"
        #refresh verification for target file!
        sha512sum $target_file > /run/eth_check.sha512
        dd if=/run/eth_check.sha512 of=${backup_file}.sha512 conv=fsync status=none
        #upgrade backup file!
        cp -af $target_file ${backup_file}
        echo upgrade eth verify and backup for $target_file
        logger_info "upgrade eth verify and backup for $target_file"
    else
        logger_info "$target_file is not need backup"
    fi
}

remove_backup_dir_file()
{
    target_file=$1
    backup_file=${backup_base_dir}/${target_file#/etc/}
    echo "backup_file is $backup_file"
    #refresh verification for target file!
    rm -f ${backup_file} ${backup_file}.sha512
    echo remove eth verify and backup for $target_file
    logger_info "remove eth verify and backup for $target_file"
}

#give a hint for modify password
if [ -f /usr/local/scripts/passwd_check.sh ];then
    /usr/local/scripts/passwd_check.sh
fi

function dir_is_need_backup()
{
    for i in $backup_dir_list
    do
        if [ "$1" == "$i" ];then
            return 1
        fi
    done
    return 0
}

if [ -e "etc/lsb-release" ] && grep -q "Ubuntu" etc/lsb-release; then
    if [ ! -d /var/spool/cron ];then
        mkdir -p /var/spool/cron
    fi

    if [ ! -d /usr/share/cracklib ];then
        mkdir -p /usr/share/cracklib
    fi
fi

#just monitor all files under /etc directory
inotifywait -mq -e moved_to,delete,close_write -r /etc /var/spool/cron/ |
while read event;
do
    #flush modify to flash
    sync
    #get the target name
    target_file=`echo $event | awk '{print $1 $3}'`
    target_dir=`echo $event | awk '{print $1}'`
    backup_flag=0
    #target in backup_file_list
    if [[ $backup_file_list =~ "$target_file" ]];then
        upgrade_backup_file $target_file
        backup_flag=1
    elif [[ $account_file_list =~ "$target_file" ]];then
        upgrade_account_file $target_file
        backup_flag=1
        #remove the hint for modify password
        if [ -f /usr/local/scripts/passwd_check.sh ];then
            /usr/local/scripts/passwd_check.sh
        fi
    else
        dir_is_need_backup $target_dir
        ret=$?
        if [ $ret -eq 1 ];then
            logger_info "$target_dir is need backup"
            target_event=`echo $event | awk '{print $2}'`
            if [[ $target_event =~ "DELETE" ]];then
                remove_backup_dir_file $target_file
            else
                upgrade_backup_dir_file $target_file
            fi
        fi
        backup_flag=1
    #target in account_file_list
    fi
    #no message record if file not in monitor list！
    if [ $backup_flag -eq 1 ];then
        target_event=`echo $event | awk '{print $2}'`
        echo [`date +%Y%m%d_%H%M%S`]:found an event $target_event ! target is $target_file
        logger_info "found an event $target_event ! target is $target_file"
        #dir modify should be write to flash
        sync
    fi
done
