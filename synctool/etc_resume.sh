#!/bin/bash

echo start etc backup

# Load log module
source /usr/local/scripts/devm_log_print.sh
# init log
init_log_path "/var/plog" "devm_scripts_run.log"

mount_os_src=""
mount_des_tmp=""

# 获取当前启动备区
function get_uboot_boot_backup_area()
{
    boot_area=`cat /proc/cmdline | awk -F 'root=' '{print $2}' | awk '{print $1}'`
    if [[ "${boot_area}" == "/dev/mmcblk0p2" ]] || [[ "${boot_area}" == "/dev/mmcblk1p2" ]]; then
            mount_os_src=${boot_area%?}3
            mount_des_tmp=/mnt/p3
    elif [[ "${boot_area}" == "/dev/mmcblk0p3" ]] || [[ "${boot_area}" == "/dev/mmcblk1p3" ]]; then
            mount_os_src=${boot_area%?}2
            mount_des_tmp=/mnt/p2
    fi
    
    cat /proc/cmdline |grep -E "PARTUUID" >/dev/null 2>&1
    if [ $? -eq 0 ]; then
        partuuid=`cat /proc/cmdline | grep -oP '(?<=PARTUUID=)[^ ]+'`
        boot_area=`readlink -f /dev/disk/by-partuuid/${partuuid}`
        if [[ "${boot_area}" == "/dev/sd"*"2" ]]; then
            mount_os_src=${boot_area%?}3
            mount_des_tmp=/mnt/p3
        elif [[ "${boot_area}" == "/dev/sd"*"3" ]]; then
            mount_os_src=${boot_area%?}2
            mount_des_tmp=/mnt/p2
        fi
    fi
}

usergroup=$(cat /etc/group | grep wheel | awk -F':' '{print $3}')
username=$(cat /etc/passwd | grep 1202:$usergroup | awk -F':' '{print $1}')
chown -h ${username}:wheel /etc/usr/sftp_disable

mkdir -p /home/data/etc/hwsipcrl
chmod 755 /home/data/etc/hwsipcrl/

sed -i "/^Cmnd_Alias NPUSMI_INFO_WATCH_CMD/c\Cmnd_Alias NPUSMI_INFO_WATCH_CMD = /usr/local/sbin/npu-smi info watch, /usr/local/sbin/npu-smi info watch -i 0,\
 /usr/local/sbin/npu-smi info watch -i 0 -c 0, /usr/local/sbin/npu-smi info watch -i 0 -c 0 -d [1-9], /usr/local/sbin/npu-smi info watch -i 0 -c 0 -d [1-9][0-9],\
 /usr/local/sbin/npu-smi info watch -i 0 -c 0 -d 100, /usr/local/sbin/npu-smi info watch -i 0 -c [0-2] -d [1-9] -s [ptaicmb],\
 /usr/local/sbin/npu-smi info watch -i 0 -c [0-2] -d [1-9][0-9] -s [ptaicmb], /usr/local/sbin/npu-smi info watch -i 0 -c [0-2] -d 100 -s [ptaicmb],\
 /usr/local/sbin/npu-smi info watch -i 0 -c [0-2] -d [1-9] -s [ptaicmb][ptaicmb], /usr/local/sbin/npu-smi info watch -i 0 -c [0-2] -d [1-9][0-9] -s [ptaicmb][ptaicmb],\
 /usr/local/sbin/npu-smi info watch -i 0 -c [0-2] -d 100 -s [ptaicmb][ptaicmb], /usr/local/sbin/npu-smi info watch -i 0 -c [0-2] -d [1-9] -s [ptaicmb][ptaicmb][ptaicmb],\
 /usr/local/sbin/npu-smi info watch -i 0 -c [0-2] -d [1-9][0-9] -s [ptaicmb][ptaicmb][ptaicmb], /usr/local/sbin/npu-smi info watch -i 0 -c [0-2] -d 100 -s [ptaicmb][ptaicmb][ptaicmb],\
 /usr/local/sbin/npu-smi info watch -i 0 -c [0-2] -d [1-9] -s [ptaicmb][ptaicmb][ptaicmb][ptaicmb],\
 /usr/local/sbin/npu-smi info watch -i 0 -c [0-2] -d [1-9][0-9] -s [ptaicmb][ptaicmb][ptaicmb][ptaicmb],\
 /usr/local/sbin/npu-smi info watch -i 0 -c [0-2] -d 100 -s [ptaicmb][ptaicmb][ptaicmb][ptaicmb],\
 /usr/local/sbin/npu-smi info watch -i 0 -c [0-2] -d [1-9] -s [ptaicmb][ptaicmb][ptaicmb][ptaicmb][ptaicmb],\
 /usr/local/sbin/npu-smi info watch -i 0 -c [0-2] -d [1-9][0-9] -s [ptaicmb][ptaicmb][ptaicmb][ptaicmb][ptaicmb],\
 /usr/local/sbin/npu-smi info watch -i 0 -c [0-2] -d 100 -s [ptaicmb][ptaicmb][ptaicmb][ptaicmb][ptaicmb],\
 /usr/local/sbin/npu-smi info watch -i 0 -c [0-2] -d [1-9] -s [ptaicmb][ptaicmb][ptaicmb][ptaicmb][ptaicmb][ptaicmb],\
 /usr/local/sbin/npu-smi info watch -i 0 -c [0-2] -d [1-9][0-9] -s [ptaicmb][ptaicmb][ptaicmb][ptaicmb][ptaicmb][ptaicmb],\
 /usr/local/sbin/npu-smi info watch -i 0 -c [0-2] -d 100 -s [ptaicmb][ptaicmb][ptaicmb][ptaicmb][ptaicmb][ptaicmb],\
 /usr/local/sbin/npu-smi info watch -i 0 -c [0-2] -d [1-9] -s [ptaicmb][ptaicmb][ptaicmb][ptaicmb][ptaicmb][ptaicmb][ptaicmb],\
 /usr/local/sbin/npu-smi info watch -i 0 -c [0-2] -d [1-9][0-9] -s [ptaicmb][ptaicmb][ptaicmb][ptaicmb][ptaicmb][ptaicmb],\
 /usr/local/sbin/npu-smi info watch -i 0 -c [0-2] -d 100 -s [ptaicmb][ptaicmb][ptaicmb][ptaicmb][ptaicmb][ptaicmb][ptaicmb],\
 /usr/local/sbin/npu-smi info -t proc-mem -i 0, /usr/local/sbin/npu-smi info -t proc-mem -i 0 -c [0-2], /usr/local/sbin/npu-smi info -t vnpu-svm -i 0,\
 /usr/local/sbin/npu-smi info -t vnpu-svm -i 0 -c [0-2], /usr/local/sbin/npu-smi info -t first-power-on-date -i 0, /usr/local/sbin/npu-smi info -t cpu-num-cfg -i 0,\
 /usr/local/sbin/npu-smi info -t cpu-num-cfg -i 0 -c [0-2], /usr/local/sbin/npu-smi info -t vnpu-cfg-recover, /usr/local/sbin/npu-smi info -t phyid-remap -p 0,\
 /usr/local/sbin/npu-smi info -t vnpu-mode, /usr/local/sbin/npu-smi info -t pwm-mode, /usr/local/sbin/npu-smi info -t pwm-duty-ratio,\
 /usr/local/sbin/npu-smi info -t mac-addr -i 0, /usr/local/sbin/npu-smi info -t mac-addr -i 0 -c 0, /usr/local/sbin/npu-smi info -t boot-select -i 0 -c 1,\
 /usr/local/sbin/npu-smi info -t template-info, /usr/local/sbin/npu-smi info -t template-info -i 0, /usr/local/sbin/npu-smi info -t work-mode -i 0" /home/data/etc/sudoers
if [[ $? == 0 ]]; then
    echo config sudoers successfully!
    rm /home/data/etc/sudoers.sha512
else
    echo config sudoers failed!
fi

mkdir -p /var/spool/cron/crontabs
if [ ! -L /home/data/etc/sysconfig/network-scripts/ifdown-isdn ];then
    rm -rf /home/data/etc/sysconfig/network-scripts/ifdown-isdn
    rm -rf /home/data/etc/sysconfig/network-scripts/ifdown-isdn.sha512
fi

if [ ! -L /home/data/etc/sysconfig/network-scripts/ifup-isdn ];then
    rm -rf /home/data/etc/sysconfig/network-scripts/ifup-isdn
    rm -rf /home/data/etc/sysconfig/network-scripts/ifup-isdn.sha512
fi

if [ ! -L /home/data/etc/sysctl.d/99-sysctl.conf ];then
    rm -rf /home/data/etc/sysctl.d/99-sysctl.conf
    rm -rf /home/data/etc/sysctl.d/99-sysctl.conf.sha512
fi

file_default_mode=0
cat /home/data/etc/rsyslog.conf | grep "$FileCreateMode 0640"
file_default_mode=$?

if [[ $file_default_mode == 0 ]];then
    sed -i "s/$FileCreateMode 0640/$FileCreateMode 0600/" /home/data/etc/rsyslog.conf
    if [[ $? == 0 ]]; then
        echo "config rsyslog.conf file create mode successfully!"
        logger_info "config rsyslog.conf file create mode successfully!"
    else
        echo "config rsyslog.conf file create mode failed!"
        logger_error "config rsyslog.conf file create mode failed!"
    fi
else
    echo "The content of /etc/rsyslog.conf is the correct configuration and will not be modified."
    logger_info "The content of /etc/rsyslog.conf is the correct configuration and will not be modified."
fi

get_uboot_boot_backup_area

# 配置文件更新切区，同步更新
if [ x"$mount_os_src" != x"" ]; then
    if [ -d "$mount_des_tmp" ];then
        umount $mount_des_tmp >/dev/null 2>&1
    else
        mkdir -p $mount_des_tmp >/dev/null 2>&1
    fi
    mount $mount_os_src $mount_des_tmp >/dev/null 2>&1
    cp -r /usr/local/scripts/backup_dir_list.txt $mount_des_tmp/usr/local/scripts/
    cp -r /usr/local/scripts/backup_file_list.txt $mount_des_tmp/usr/local/scripts/
    umount $mount_des_tmp >/dev/null 2>&1
    logger_info "update backup_dir_list.txt and backup_file_list.txt $mount_os_src."
fi

/usr/local/scripts/config_resume.sh

chmod a+r /etc/passwd
hostname -F /etc/hostname

/usr/local/scripts/etc_backup.sh &

if [ -e "etc/lsb-release" ] && grep -q "Ubuntu" etc/lsb-release; then
    netplan apply &
fi

exit 0
