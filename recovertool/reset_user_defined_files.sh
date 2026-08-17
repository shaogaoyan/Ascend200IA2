#!/bin/bash
#########################readme###########################################
# This script is used to guide you to be restored to the Golden partition
# to be added during file system creation.

# Attention:
# ROOT_PATH must be $1(the fisrt para)
# BOOT_SH must be "${ROOT_PATH}/var/minirc_hook.sh"

# Scripts name:
# you hook scripts name must be minirc_install_hook.sh
##########################################################################

golden_mount_point=/mnt/mmc/p1
p2_mount_point=/mnt/mmc/p2
p3_mount_point=/mnt/mmc/p3
decompress_tar_dir="/run/restore"
user_tar_pkg=""

if [ "$1" != "$golden_mount_point" ];then
    echo "golden partition mount point is error."
    exit 1
fi

source "$golden_mount_point"/restore_factory_common.sh

mount_golden_parttion
ret=$?
if [ $ret -ne 0 ];then
    exit $ret
fi

function decompress_user_pkgs()
{
    user_tar_pkg=$(ls -t $golden_mount_point/Ascend-hdk-310b-user-defined.tar.gz | head -n1)
    if [ -z "$user_tar_pkg" ];then
        echo "$(date +"%Y-%m-%d %H:%M:%S") Can not find tar pkgs form $component_back_dir."
        restore_log "Can not find tar pkgs form $golden_mount_point."
        return 1
    fi

    file_valid_check $user_tar_pkg
    ret=$?
    if [ $ret -ne 0 ];then
        return 1
    fi

    #Decompressing and Upgrading Tar Package
    rm -rf $decompress_tar_dir
    mkdir -p $decompress_tar_dir
    cd $decompress_tar_dir
    tar zxf $user_tar_pkg -C ./
    return 0
}

###############################################################

########################user function##########################
# if you need restore something to the Golden partition,
# make sure you really want to do this during factory restoration.
function copy_user_defined_files()
{

}

function reset_user_defined_files()
{
    local target_mount_point=/mnt/mmc/p${1}
    local mount_point
    mount_point=$(df -h | grep "/dev/${mmc}${p_letter}${1}" | awk '{print $6}')
    if [ -z "$mount_point" ];then
        restore_log "p${1} is not mount, now continue."
    else
        umount "$mount_point"
    fi

    mount -t ext4 /dev/${mmc}${p_letter}${1} $target_mount_point
    ret=$?
    if [ $ret -ne 0 ];then
        restore_log "mount p${1} failed."
        return 1
    fi

    cd $target_mount_point
    copy_user_defined_files
    ret=$?
    if [ $ret -ne 0 ];then
        exit $ret
    fi

    cd - >& /dev/null
    umount $target_mount_point
    restore_log "p${1} reset user_defined files complete."
    return 0
}

decompress_user_pkgs
ret=$?
if [ $ret -ne 0 ];then
    exit $ret
fi

for ((i=2;i<=3;i++))
do
    reset_user_defined_files $i
    ret=$?
    if [ $ret -ne 0 ];then
        exit $ret
    fi
done

exit 0
