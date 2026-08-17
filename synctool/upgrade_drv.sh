#!/bin/bash
#驱动升级总入口脚本，支持npu独立升级
CUR_DIR=$(dirname $(readlink -f $0))

#用户输入参数
operation_type=$1
upgrade_drv_file=$2
upgrade_cms_file=$3
upgrade_crl_file=$4
upgradeprogress=$5

#全局配置
decompress_tar_dir="/run/upgrade/driver"
upgrade_file_type=""
logfile="/var/plog/upgrade.log"
uboot_boot_nor_spi=0
update_dir=""
mount_des_main_tmp=/mnt/p2
mount_des_backup_tmp=/mnt/p3
mount_os_src_main=/dev/mmcblk0p2
mount_os_src_backup=/dev/mmcblk0p3

#/dev/mmcblk1p4 --> /home/data/ 持久化数据
npu_active_file="/home/data/upgrade/npu_active"

#/dev/mmcblk1p7 --> /home/package 安装包的存储区
npu_package_back_dir="/home/package/npu"

#npu zip包解压目录
decompress_npu_tar_dir="$decompress_tar_dir/npu"

mcu_upgrade_tools=npu-smi

function log()
{
    #检查升级文件是否存在
    if [ ! -f "$logfile" ];then
        touch $logfile
    fi
    chmod 640 $logfile
    cur_date=`date +"%Y-%m-%d %H:%M:%S"`
    echo "$cur_date "$1 >> $logfile
}

#*****************************************************************************
# Description  : 获取os启动区
#*****************************************************************************
function get_uboot_boot_area()
{
    #emmc做启动介质获取os启动区
    cat /proc/cmdline | grep "/dev/mmcblk0p2" > /dev/null
    if [ $? -eq 0 ];then
        log "boot area is mmcblk0p2"
        return 0
    fi

    cat /proc/cmdline | grep "/dev/mmcblk0p3" > /dev/null
    if [ $? -eq 0 ];then
        log "boot area is mmcblk0p3"
        return 1
    fi

    #sd卡做启动介质获取os启动区
    cat /proc/cmdline | grep "/dev/mmcblk1p2" > /dev/null
    if [ $? -eq 0 ];then
        mount_os_src_main=/dev/mmcblk1p2
        mount_os_src_backup=/dev/mmcblk1p3
        log "boot area is mmcblk1p2"
        return 0
    fi

    cat /proc/cmdline | grep "/dev/mmcblk1p3" > /dev/null
    if [ $? -eq 0 ];then
        mount_os_src_main=/dev/mmcblk1p2
        mount_os_src_backup=/dev/mmcblk1p3
        log "boot area is mmcblk1p3"
        return 1
    fi

    #M.2盘做启动介质获取os启动区
    cat /proc/cmdline |grep -E "PARTUUID" >/dev/null 2>&1
    if [ $? -eq 0 ]; then
        partuuid=`cat /proc/cmdline | grep -oP '(?<=PARTUUID=)[^ ]+'`
        boot_area=`readlink -f /dev/disk/by-partuuid/${partuuid}`
        mount_os_src_main=${boot_area%?}2
        mount_os_src_backup=${boot_area%?}3

        if [[ "${boot_area}" == "/dev/sd"*"2" ]]; then
            log "boot area is ${boot_area}"
            return 0
        elif [[ "${boot_area}" == "/dev/sd"*"3" ]]; then
            log "boot area is ${boot_area}"
            return 1
        fi
    fi

    log "df get boot fail"
    df >>$logfile

    return 2
}

function mount_backup_area() {
    local cur_boot_area=0

    get_uboot_boot_area
    cur_boot_area=$?
    if [ $cur_boot_area -ne 0 ] &&  [ $cur_boot_area -ne 1 ];then
        log "mount_backup_area, get_uboot_boot_area fail,ret=$cur_boot_area"
        return 1
    fi

    uboot_boot_nor_spi=$cur_boot_area

    #mount p2或p3区到临时目录
    if [ $cur_boot_area -eq 0 ];then
        if [ -d "$mount_des_backup_tmp" ];then
            umount $mount_des_backup_tmp >>$logfile 2>&1
        else
            mkdir -p $mount_des_backup_tmp >>$logfile 2>&1
        fi
        mount  $mount_os_src_backup $mount_des_backup_tmp >>$logfile 2>&1
        if [ $? -ne 0 ];then
            log "[Error]Failed,mount_backup_area, mount $mount_os_src_backup to $mount_des_backup_tmp fail"
            mkfs.ext4 -F $mount_os_src_backup >>$logfile 2>&1
            mount  $mount_os_src_backup $mount_des_backup_tmp >>$logfile 2>&1
            if [ $? -eq 0 ];then
                echo "recover $mount_os_src_backup and mount successfully." >> $logfile
            else
                log "[Error]Failed,mount_backup_area, mount $mount_os_src_backup to $mount_des_backup_tmp fail"
                return 2
            fi
        fi
        update_dir=$mount_des_backup_tmp
    else
        if [ -d "$mount_des_main_tmp" ];then
            umount $mount_des_main_tmp >>$logfile 2>&1
        else
            mkdir -p $mount_des_main_tmp >>$logfile 2>&1
        fi
        mount  $mount_os_src_main $mount_des_main_tmp >>$logfile 2>&1
        if [ $? -ne 0 ];then
            log "[Error]Failed,mount_backup_area, mount $mount_os_src_main to $mount_des_main_tmp fail"
            mkfs.ext4 -F $mount_os_src_main >>$logfile 2>&1
            mount  $mount_os_src_main $mount_des_main_tmp >>$logfile 2>&1
            if [ $? -eq 0 ];then
                echo "recover $mount_os_src_main and mount successfully." >> $logfile
            else
                log "[Error]Failed,mount_backup_area, mount $mount_os_src_main to $mount_des_main_tmp fail"
                return 3
            fi
        fi
        update_dir=$mount_des_main_tmp
    fi
    return 0
}

#卸载P2P3备区分区
function umount_backup_area() {
    cd /
    if [ $uboot_boot_nor_spi -eq 0 ];then
        mountted_des=$mount_des_backup_tmp
    else
        mountted_des=$mount_des_main_tmp
    fi

    umount $mountted_des >>$logfile 2>&1
    if [ $? -ne 0 ];then
        log "umount_backup_area, umount $mountted_des fail"
    fi
    cd - >/dev/null
}

function set_os_boot_from_bak_area()
{
    boot_tool set swap_region
    ret=$?
    if [ $ret -ne 0 ];then
        log "boot_tool fail, ret=$ret"
        return 1
    fi

    return 0
}

function set_sync_active_flag()
{
    if [ "${upgrade_file_type}" == "NPU" ]; then
        mkdir -p `dirname ${npu_active_file}`
        touch $npu_active_file
        log "set npu sync active flag success."
        return 0
    fi

    log "set $upgrade_file_type sync active flag fail."
    return 1
}

#同步完成后清理临时文件
function cleanup_sync_active_flag()
{
    rm -f $npu_active_file
}

function file_valid_check()
{
    #检查文件是否存在
    if [ ! -f "$1" ];then
        echo "file is not exist"
        return 1
    fi

    #检查文件是否为符号链接
    if [ -L "$1" ];then
        echo "file $1 cannot be a soft link."
        return 1
    fi

    #检查文件所有者的用户名是否为root
    owner=$(stat -c %U "$1")
    if [ "${owner}" != "root" ]; then
        log "$1 permision isn't right, it should belong to root."
        return 1
    fi

    return 0
}

#校验传入的文件是否支持升级，模组制卡只支持升级NPU
function check_file_is_support_upgrade()
{
    local support_upgrade_file_type=("NPU")
    #解析version.xml中<FileType>xxx</FileType>字段获取当前固件类型
    upgrade_file_type=`cat version.xml | grep FileType | sed 's/^.*<FileType>//g' | sed 's/<\/FileType>.*$//g'`

    for ((j=0; j<${#support_upgrade_file_type[*]}; j++))
    do
        if [[ "$upgrade_file_type" =~ "${support_upgrade_file_type[$j]}" ]]; then
            log "upgrade type is $upgrade_file_type."
            echo "$(date +"%Y-%m-%d %H:%M:%S") upgrade type is $upgrade_file_type."
            return 0
        fi
    done

    echo "$(date +"%Y-%m-%d %H:%M:%S") upgrade of $upgrade_file_type is not supported."
    log "upgrade of $upgrade_file_type is not supported."
    return 1
}

upgrade_file_permision_check()
{
    #检查文件是否存在
    if [ ! -f "$upgrade_drv_file" ] || [ ! -f "$upgrade_cms_file" ] || [ ! -f "$upgrade_crl_file" ];then
        echo "$(date +"%Y-%m-%d %H:%M:%S") upgrade file is not exist."
        log "upgrade file is not exist."
        return 1
    fi

    #检查文件是否为符号链接
    if [ -L "$upgrade_drv_file" ] || [ -L "$upgrade_cms_file" ] || [ -L "$upgrade_crl_file" ];then
        echo "$(date +"%Y-%m-%d %H:%M:%S") upgrade file cannot be a soft link."
        log "upgrade file cannot be a soft link."
        return 1
    fi

    #检查文件所有者的用户名是否为root
    owner=$(stat -c %U "$upgrade_drv_file")
    if [ "${owner}" != "root" ]; then
        echo "$(date +"%Y-%m-%d %H:%M:%S") $upgrade_drv_file permision isn't right, it should belong to root."
        log "$upgrade_drv_file permision isn't right, it should belong to root."
        return 1
    fi

    owner=$(stat -c %U "$upgrade_cms_file")
    if [ "${owner}" != "root" ]; then
        echo "$(date +"%Y-%m-%d %H:%M:%S") $upgrade_cms_file permision isn't right, it should belong to root."
        log "$upgrade_cms_file permision isn't right, it should belong to root."
        return 1
    fi

    owner=$(stat -c %U "$upgrade_crl_file")
    if [ "${owner}" != "root" ]; then
        echo "$(date +"%Y-%m-%d %H:%M:%S") $upgrade_crl_file permision isn't right, it should belong to root."
        log "$upgrade_crl_file permision isn't right, it should belong to root."
        return 1
    fi

    return 0
}

function upgrade_process_main()
{
    echo "$(date +"%Y-%m-%d %H:%M:%S") upgrade in progress,please wait...."
    log "upgrade in progress,please wait...."

    #升级前文件检查
    upgrade_file_permision_check
    ret=$?
    if [ $ret -ne 0 ];then
        echo "$(date +"%Y-%m-%d %H:%M:%S") Failed to check the permission of the upgrade file"
        return $ret
    fi

    #清理驱动升级临时文件
    rm -rf $decompress_tar_dir

    #解压升级tar包
    mkdir -p $decompress_tar_dir
    cd $decompress_tar_dir
    tar zxf $upgrade_drv_file -C ./

    #校验是否支持此固件升级
    check_file_is_support_upgrade
    ret=$?
    if [ $ret -ne 0 ];then
        echo "$(date +"%Y-%m-%d %H:%M:%S") Failed to check whether the file supports the upgrade"
        return $ret
    fi

    #mount备区
    mount_backup_area
    ret=$?
    if [ $ret -ne 0 ]; then
        echo "$(date +"%Y-%m-%d %H:%M:%S") mount backup area error, please check the log, log path is /var/plog/upgrade.log"
        return $ret
    fi

    #升级备区固件版本
    source ./upgrade.sh $operation_type $upgrade_drv_file $upgrade_cms_file $upgrade_crl_file golden_upgrade_no
    ret=$?
    if [ $ret -ne 0 ];then
        umount_backup_area
        echo "$(date +"%Y-%m-%d %H:%M:%S") upgrade driver failed, please check the log, log path is /var/plog/upgrade.log"
        return $ret
    fi

    #设置主备同步标志
    set_sync_active_flag
    ret=$?
    if [ $ret -ne 0 ];then
        umount_backup_area
        echo "$(date +"%Y-%m-%d %H:%M:%S") Failed to set sync active flag"
        return $ret
    fi

    #升级完成后，切换启动分区（bootA/p2、bootB/p3）。下次从对区启动
    set_os_boot_from_bak_area
    ret=$?
    if [ $ret -ne 0 ];then
        umount_backup_area
        echo "$(date +"%Y-%m-%d %H:%M:%S") Failed to set os boot from bak area"
        return $ret
    fi

    umount_backup_area

    echo "$(date +"%Y-%m-%d %H:%M:%S") user upgrade success"
    log "user upgrade success"
}

function synchronize_process_sub_component()
{
    echo "$(date +"%Y-%m-%d %H:%M:%S")  synchronize $update_dir start..."
    component_back_dir=$1
    component_tar_pkg_name=$(find $component_back_dir -name "*.tar.gz" )
    if [ -z "$component_tar_pkg_name" ];then
        echo "$(date +"%Y-%m-%d %H:%M:%S") Can not find tar pkgs form $component_back_dir."
        return 1
    fi
    upgrade_drv_file="$component_tar_pkg_name"
    upgrade_cms_file="$component_tar_pkg_name".cms
    upgrade_crl_file="$component_tar_pkg_name".crl

    upgrade_file_permision_check
    ret=$?
    if [ $ret -ne 0 ];then
        return 1
    fi

    #解压升级tar包
    rm -rf $decompress_tar_dir
    mkdir -p $decompress_tar_dir
    cd $decompress_tar_dir
    tar zxf $upgrade_drv_file -C ./

    #mount备区
    mount_backup_area
    ret=$?
    if [ $ret -ne 0 ]; then
        echo "$(date +"%Y-%m-%d %H:%M:%S") mount backup area error, please check the log, log path is /var/plog/upgrade.log"
        return 1
    fi
    pwd
    #升级备区固件版本
    source ./upgrade.sh $operation_type $upgrade_drv_file $upgrade_cms_file $upgrade_crl_file golden_upgrade_no
    ret=$?
    if [ $ret -ne 0 ];then
        umount_backup_area
        echo "$(date +"%Y-%m-%d %H:%M:%S") upgrade driver failed, please check the log, log path is /var/plog/upgrade.log"
        return 1
    fi

    #同步升级对区成功后清理同步标志
    cleanup_sync_active_flag

    umount_backup_area
    echo "$(date +"%Y-%m-%d %H:%M:%S")  synchronize $update_dir success"
    return 0
}

function synchronize_process_main()
{
    if [ -f "$npu_active_file" ];then
        file_valid_check "$npu_active_file"
        ret=$?
        if [ $ret -eq 0 ];then
            synchronize_process_sub_component "$npu_package_back_dir"
            ret=$?
            return $ret
        else
            return 1
        fi
    else
        return 0
    fi
}

function upgrade_drv_main()
{
    echo "$(date +"%Y-%m-%d %H:%M:%S") start upgrade_drv.sh"
    log "start upgrade_drv.sh"

    if [ "$operation_type" == "-u" ];then
        # 升级
        mkdir -p /home/data/upgrade
        touch /home/data/upgrade/upgrade_flag
        upgrade_process_main
        ret=$?
        if [ $ret -ne 0 ];then
            echo "$(date +"%Y-%m-%d %H:%M:%S") upgrade process fail"
            rm -f /home/data/upgrade/upgrade_flag
            exit $ret
        fi

        rm -f /home/data/upgrade/upgrade_flag
        echo "$(date +"%Y-%m-%d %H:%M:%S") end upgrade_drv.sh"
        log "end upgrade_drv.sh"
        exit 0
    fi

    if [ "$operation_type" == "-s" ];then
        # 同步
        synchronize_process_main
        ret=$?
        if [ $ret -ne 0 ];then
            echo "$(date +"%Y-%m-%d %H:%M:%S") synchronize process fail"
            exit $ret
        fi

        echo "$(date +"%Y-%m-%d %H:%M:%S") end upgrade_drv.sh"
        log "end upgrade_drv.sh"
        exit 0
    fi

    echo "$(date +"%Y-%m-%d %H:%M:%S") end upgrade_drv.sh"
    log "end upgrade_drv.sh"
}

upgrade_drv_main