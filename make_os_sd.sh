#!/bin/bash
# ************************Variable*********************************************
ScriptPath="$( cd "$(dirname "$0")" ; pwd -P )""/"
DEV_NAME=$1
MAKECONF="mksd.conf"
#********************** UPDATE TO FIX ISSUE REGARDING /dev/mmc* MOUNTED SD CARD **********

if [[ $DEV_NAME == /dev/mmc* ]]
then
    echo "Partion naming with p-prefix"
    p1="p1"
    p2="p2"
    p3="p3"
    p4="p4"
    p5="p5"
else
    echo "Partition naming without p-prefix"
    p1="1"
    p2="2"
    p3="3"
    p4="4"
    p5="5"
fi

#####################################################################################


ISO_FILE_DIR=$2
ISO_FILE=$3

NETWORK_CARD_DEFAULT_IP=$4
NETWORK_CIDR_PREFIX=$5
NETWORK_DEFAULT_NETMASK=$6
NETWORK_DEFAULT_GATEWAY=$7
USB_CARD_DEFAULT_IP=$8

MAKE_OS_RESULT=$9
CARD_TYPE=${10}

LogPath=${ScriptPath}"sd_card_making_log/"
TMPDIR_SD_MOUNT=${LogPath}"sd_mount_dir"
TMPDIR_SD2_MOUNT=${LogPath}"sd_mount_dir2"
TMPDIR_SD3_MOUNT=${LogPath}"sd_mount_dir3"
TMPDIR_SD4_MOUNT=${LogPath}"sd_mount_dir4"
TMPDIR_DATE=${LogPath}"no_touch_make_sd_dir"

USER_NAME="HwHiAiUser"
SYS_USER="HwSysUser"
DM_USER="HwDmUser"
BASE_USER="HwBaseUser"
USER_PWD="HwHiAiUser:\$6\$klSpdQ1K\$4Gm/7HxehX.YSum4Wf3IDFZ3v5L.clybUpGNGaw9zAh3rqzqB4mWbxvSTFcvhbjY/6.tlgHhWsbtbAVNR9TSI/:17795:0:99999:7:::"
ROOT_PWD="root:\$6\$klSpdQ1K\$4Gm/7HxehX.YSum4Wf3IDFZ3v5L.clybUpGNGaw9zAh3rqzqB4mWbxvSTFcvhbjY/6.tlgHhWsbtbAVNR9TSI/:17795:0:99999:7:::"
ADMIN_PWD="admin:\$6\$jxREBBrxbdTgGkE9\$4m0eSh/oBuZSXnYYrX.uzwUdpbxMSSegBmZq5uJDMnNPLkTumRgth6JLBAYS7Rf4KF5tOmihk8oJ9.2hrjtAF0:19574:0:365:7:::"

MINIRC_LOGROTATE_DIR="/etc/crob.minirc/"
SYSLOG_MAXSIZE="1000M"
SYSLOG_ROTATE="4"
KERNLOG_MAXSIZE="1000M"
KERNLOG_ROTATE="4"
MAKE_IMGPK_FLAG="off"
FAST_BOOT_FLAG="off"
FLAG_310B="off"
DRIVER_PACKAGE=$(ls Ascend*310*driver*.*)

if [ x"CARD_TYPE" == x"" ];then
    CARD_TYPE="SD"
fi

if [ "$CARD_TYPE"x == "NVME"x ];then
    suffix="p"
else
    suffix=""
fi

if [ $DEV_NAME == "vdisk" ];then
    which losetup >/dev/null 2>&1 || { echo "Failed: command(losetup) not found." && exit 1; }
    which kpartx >/dev/null 2>&1 || { echo "Failed: command(kpartx) not found." && exit 1; }
    MAKE_IMGPK_FLAG="on"
    FAST_BOOT_FLAG=$(cat ${MAKECONF} |  grep FAST_BOOT_FLAG |  awk -F "=" '{ print $2 }')
    #4751360sectors is 2320M
    sectorEnd="4751360"
    sectorSize="512"
    recoverfilepath=${ScriptPath}"recovertool"
    if [ ! -d ${recoverfilepath} ];then
        echo "Failed: recovertool directory is not exit, please create and place the file."
        exit 1
    fi
    pk_driver=$(ls ${recoverfilepath}/Ascend-hdk-310b-npu-soc*.tar.gz)
    pk_hdm=$(ls ${recoverfilepath}/A500-A2-hdm_*.tar.gz)
    pk_user_defined=$(ls ${recoverfilepath}/Ascend-hdk-310b-user-defined.tar.gz)
    pk_om=$(ls ${recoverfilepath}/Ascend-mindxedge-om*linux-aarch64.tar.gz)
    pk_mefedge=$(ls ${recoverfilepath}/Ascend-mindxedge-mefedge*linux-aarch64.tar.gz)
    pk_toolbox=$(ls ${recoverfilepath}/Ascend-mindx-toolbox*linux-aarch64.tar.gz)
    pk_cann=$(ls ${recoverfilepath}/Ascend-cann-nnrt_*_linux-aarch64.tar.gz)

    [ -n "${pk_driver}" ] || { echo "Failed: 310b-npu-soc.tar.gz not found." && exit 1; }

    if [ -f ${recoverfilepath}/restore_factory.sh ];then
        minPNUM="8"
        actualP=`cat ${recoverfilepath}/restore_factory.sh | grep "P_MAX_PN=" | awk -F '=' '{print $2}'`
        [ "${actualP}" -lt ${minPNUM} ] && { echo "Failed: partition nums less than minPNUM." && exit 1; }
    fi

    user_filesize=$(stat -c%s "$pk_user_defined")
    [ "${user_filesize}" -gt 209715200 ] && { echo "Failed: user-defined.tar.gz is greater than 200 MB." && exit 1; }

else
    sectorEnd=`fdisk -l | grep "$DEV_NAME:" | awk -F ' ' '{print $7}'`
    sectorSize=`fdisk -l | grep -A 2 "$DEV_NAME:" | grep "Units" | awk -F ' ' '{print $6}'`
    if [ $sectorSize -ne 512 ];then
        echo "Failed: sector size is not 512!"
        exit 1
    fi
fi

if [[ ${DRIVER_PACKAGE}"X" == "X" ]];then
    echo "Failed: Can not find driver package: Ascend*310*driver*.*"
    exit 1
fi

if [ $DRIVER_PACKAGE = "$(ls Ascend*310b*driver* 2>/dev/null)" ];then
    FLAG_310B="on"
fi

function checkChipType()
{
    if [ "$FLAG_310B"x = "on"x ];then
        # 822083584 bytes is 784M
        sectorRsv=$[822083584/sectorSize+1]
        #format card need reserver 100 sector
        sectorEnd=$[sectorEnd-100]
        # 16777216 bytes is 16M, reserved for struct info
        BOOTIMG_OFFSET_A=$[16777216/sectorSize]
        #150994944 bytes is 144M, reserved for kernel/dtb/tee
        BOOTIMG_OFFSET_B=$[150994944/sectorSize]
        #285212672 bytes is 272M, reserved for kernel/dtb/tee bak
        RECOVER_BOOTIMG_OFFSET_E=$[285212672/sectorSize]
        #553648128 bytes is 528M, reserved for kernel/dtb/initrd
        RECOVER_BOOTIMG_OFFSET_F=$[553648128/sectorSize]

        #0 30M
        IMAGE_OFFSET=0
        IMAGE_SIZE=61440
        #40M 2M
        DTB_OFFSET=81920
        DTB_SIZE=4096
        #44M 4M
        TEE_OFFSET=90112
        TEE_SIZE=8192
        #48M 80M
        INITRD_OFFSET=98304
        INITRD_SIZE=163840
        # end
        return 0
    fi

    # 536870912 bytes is 512M
    sectorRsv=$[536870912/sectorSize+1]
    sectorEnd=$[sectorEnd-sectorRsv]

    #component main/backup offset
    COMPONENTS_MAIN_OFFSET=$[sectorEnd+1]
    COMPONENTS_BACKUP_OFFSET=$[COMPONENTS_MAIN_OFFSET+73728]
    #0 512k
    LPM3_OFFSET=0
    LPM3_SIZE=1024
    #1M 512k
    TEE_OFFSET=2048
    TEE_SIZE=1024
    #2M 2M
    DTB_OFFSET=4096
    DTB_SIZE=4096
    #32M 32M
    IMAGE_OFFSET=8192
    IMAGE_SIZE=65536
    # end
}

# ************************configure*********************************************
# Description:  configure
# ******************************************************************************
function checkConfig()
{
    source ${MAKECONF} || \
        { echo "Failed: ${MAKECONF} may has something wrong, please check and repair." && return 1; }
    echo "record ${MAKECONF}" && cat ${MAKECONF}
    return 0
}
# ************************Cleanup*********************************************
# Description:  files cleanup
# ******************************************************************************
function checkDirMnt
{
    local dirmnt="$1"
    df -h | grep "$dirmnt"
    if [ $? -eq 0 ];then
        umount $dirmnt
    fi
    rm -rf $dirmnt
}

function filesClean()
{
    checkDirMnt ${TMPDIR_DATE}
    checkDirMnt ${LogPath}squashfs-root/cdtmp
    checkDirMnt ${TMPDIR_SD_MOUNT}
    checkDirMnt ${TMPDIR_SD2_MOUNT}
    checkDirMnt ${TMPDIR_SD3_MOUNT}
    checkDirMnt ${TMPDIR_SD4_MOUNT}

    if [ "$FLAG_310B"x = "on"x ] && [ $MAKE_IMGPK_FLAG = "on" ];then
        checkDirMnt ${LogPath}recoverMntdir
        kpartx -d $loopdevice 2>/dev/null
        losetup -d $loopdevice 2>/dev/null
    fi
    rm -rf $Install_Cache_Path_Param
    rm -rf ${LogPath}squashfs-root
    rm -rf ${LogPath}filesystem.squashfs
    rm -rf ${LogPath}ubuntu-server-minimal.squashfs
    rm -rf ${LogPath}driver
    if [ "$FLAG_310B"x = "on"x ];then
        rm -rf $Install_Cache_Path_Param
    fi
    return 0
}
#end
# ************************check ip****************************************
# Description:  check ip valid or not
# $1: ip
# ******************************************************************************
function checkIpAddr()
{
    ip_addr=$1
    echo ${ip_addr} | grep "^[0-9]\{1,3\}\.\([0-9]\{1,3\}\.\)\{2\}[0-9]\{1,3\}$" > /dev/null
    if [ $? -ne 0 ]
    then
        return 1
    fi

    for num in `echo ${ip_addr} | sed "s/./ /g"`
    do
        if [ $num -gt 255 ] || [ $num -lt 0 ]
        then
            return 1
        fi
   done
   return 0
}

# **************check network card and usb card ip******************************
# Description:  check network card and usb card ip
# ******************************************************************************
function checkIps()
{
    if [[ ${NETWORK_CARD_DEFAULT_IP}"X" == "X" ]];then
        NETWORK_CARD_DEFAULT_IP="192.168.0.2"
    fi

    checkIpAddr ${NETWORK_CARD_DEFAULT_IP}
    if [ $? -ne 0 ];then
        echo "Failed: Invalid network card ip."
        return 1
    fi


    if [[ ${USB_CARD_DEFAULT_IP}"X" == "X" ]];then
        USB_CARD_DEFAULT_IP="192.168.1.2"
    fi

    checkIpAddr ${USB_CARD_DEFAULT_IP}
    if [ $? -ne 0 ];then
        echo "Failed: Invalid usb card ip."
        return 1
    fi
    USB_CARD_GATEWAY=`echo ${USB_CARD_DEFAULT_IP} | sed -r 's/([0-9]+\.[0-9]+\.[0-9]+)\.[0-9]+/\1.1/g'`
    return 0
}

# **************check driver package and ubuntu iso******************************
# Description:  check driver package and ubuntu iso: file exist, version match
# ******************************************************************************
function checkPackage()
{
    if [[ $ISO_FILE =~ "22.04" ]];then
        PACKAGE_VERSION="22.04"
        OS_TYPE="Ubuntu"
        ISO_SOURCE_VERSION="jammy main restricted"
        NETWORK_CFG_FILE="/etc/netplan/01-netcfg.yaml"
        NETWORK_CONFIG="
network:
  version: 2
  renderer: networkd
  ethernets:
    eth0:
      dhcp4: no
      addresses: [${NETWORK_CARD_DEFAULT_IP}/${NETWORK_CIDR_PREFIX}]
      gateway4: ${NETWORK_DEFAULT_GATEWAY}

    usb0:
      dhcp4: no
      addresses: [${USB_CARD_DEFAULT_IP}/24]
      gateway4: ${USB_CARD_GATEWAY}
"
NETWORK_CONFIG_ETH1="    eth1:
      dhcp4: no
      addresses: [192.168.3.111/24]
"
    elif [[ $ISO_FILE =~ "18.04" ]];then
        PACKAGE_VERSION="18.04"
        OS_TYPE="Ubuntu"
        ISO_SOURCE_VERSION="bionic main restricted"
        NETWORK_CFG_FILE="/etc/netplan/01-netcfg.yaml"
        NETWORK_CONFIG="
network:
  version: 2
  renderer: networkd
  ethernets:
    eth0:
      dhcp4: no
      addresses: [${NETWORK_CARD_DEFAULT_IP}/${NETWORK_CIDR_PREFIX}]
      gateway4: ${NETWORK_DEFAULT_GATEWAY}

    usb0:
      dhcp4: no
      addresses: [${USB_CARD_DEFAULT_IP}/24]
      gateway4: ${USB_CARD_GATEWAY}
"
    elif [[ $ISO_FILE =~ "16.04" ]];then
        PACKAGE_VERSION="16.04"
        ISO_SOURCE_VERSION="xenial main restrict"
        NETWORK_CFG_FILE="/etc/network/interfaces"
        OS_TYPE="Ubuntu"
        NETWORK_CONFIG="source /etc/network/interfaces.d/*
auto lo
iface lo inet loopback

auto eth0
iface eth0 inet static
address ${NETWORK_CARD_DEFAULT_IP}
netmask ${NETWORK_DEFAULT_NETMASK}
gateway ${NETWORK_DEFAULT_GATEWAY}

auto usb0
iface usb0 inet static
address ${USB_CARD_DEFAULT_IP}
netmask ${USB_CARD_GATEWAY}
"
    elif [[ $ISO_FILE =~ "EulerOS" ]];then
        PACKAGE_VERSION=""
        ISO_SOURCE_VERSION=""
        OS_TYPE="EulerOS"
        NETWORK_CFG_FILE="/etc/sysconfig/network-scripts/ifcfg-eth0"
        NETWORK_CONFIG="
TYPE=Ethernet
BOOTPROTO=static
DEFROUTE=yes
NAME=eth0
DEVICE=eth0
ONBOOT=yes
IPADDR=${NETWORK_CARD_DEFAULT_IP}
NETMASK=${NETWORK_DEFAULT_NETMASK}
GATEWAY=${NETWORK_DEFAULT_GATEWAY}
"
    elif [[ $ISO_FILE =~ "openEuler" ]];then
        PACKAGE_VERSION=""
        ISO_SOURCE_VERSION=""
        OS_TYPE="openEuler"
        NETWORK_CFG_FILE="/etc/sysconfig/network-scripts/ifcfg-eth0"
        NETWORK_CONFIG="
TYPE=Ethernet
BOOTPROTO=static
DEFROUTE=yes
NAME=eth0
DEVICE=eth0
ONBOOT=yes
IPADDR=${NETWORK_CARD_DEFAULT_IP}
NETMASK=${NETWORK_DEFAULT_NETMASK}
GATEWAY=${NETWORK_DEFAULT_GATEWAY}
"
        NETWORK_CONFIG_ETH1="
TYPE=Ethernet
BOOTPROTO=static
DEFROUTE=yes
NAME=eth1
DEVICE=eth1
ONBOOT=yes
IPADDR=192.168.3.111
NETMASK=255.255.255.0
"
        NETWORK_CONFIG_USB0="
TYPE=Ethernet
BOOTPROTO=dhcp
DEFROUTE=yes
NAME=usb0
DEVICE=usb0
ONBOOT=no
"
    else
        echo "unknown ISO version!!!"
        return 1
    fi

    return 0
}

# ************************umount SD Card****************************************
# Description:  check sd card mount, if mounted, umount it
# ******************************************************************************
function checkSDCard()
{
    paths=`df -h | grep "$DEV_NAME" | awk -F ' ' '{print $6}'`
    for path in $paths
    do
        echo "umount $path"
        umount $path
        if [ $? -ne 0 ];then
            echo "Failed: umount $path failed!"
            return 1
        fi
    done
    return 0
}
#end

# ************************Extract ubuntufs from iso*****************************
# Description:  mount iso file , extract root filesystem from squashfs, after
# execute function it will create squashfs-root/ in "./"
# ******************************************************************************
function ubuntufsExtract()
{
    rootfs_openeuler2203="Sample-root-filesystem-soc_openEuler-22.03-LTS*-aarch64.img"
    rootfs_ubuntu2204="Sample-root-filesystem-soc_ubuntu-22.04-aarch64.img"
    mkdir ${TMPDIR_DATE}
    mount -o loop ${ISO_FILE_DIR}/${ISO_FILE} ${TMPDIR_DATE}

    if [[ $ISO_FILE =~ "ubuntu-22.04" ]];then
        cd ${LogPath}
        mkdir squashfs-root
        cd squashfs-root
        zcat ${ISO_FILE_DIR}/$rootfs_ubuntu2204 | cpio -divm
        if [[ $? -ne 0 ]];then
            echo "Failed: cpio file fail!"
            return 1;
        fi
        cd -
    elif [[ $ISO_FILE =~ "ubuntu" ]];then
        cp ${TMPDIR_DATE}/install/filesystem.squashfs ${LogPath}
        if [[ $? -ne 0 ]];then
            echo "Failed: Copy 'filesystem.squashfs' fail!"
            return 1;
        fi

        cd ${LogPath}
        unsquashfs filesystem.squashfs

        if [[ $? -ne 0 ]];then
            echo "Failed: Unsquashfs 'filesystem.squashfs' fail!"
            return 1;
        fi
    elif [[ $ISO_FILE =~ "EulerOS" ]];then
        cd ${LogPath}
        mkdir squashfs-root
        cd squashfs-root
        zcat ${ISO_FILE_DIR}/initrd | cpio -divm

        if [[ $? -ne 0 ]];then
            echo "Failed: cpio file fail!"
            return 1;
        fi
        cd -
    elif [[ $ISO_FILE =~ "openEuler" ]];then
        cd ${LogPath}
        mkdir squashfs-root
        cd squashfs-root
        zcat ${ISO_FILE_DIR}/$rootfs_openeuler2203 | cpio -divm
        if [[ $? -ne 0 ]];then
            echo "Failed: cpio file fail!"
            return 1;
        fi
        cd -
    else
        echo "Failed: iso file not match!"
        return 1;
    fi
    #Return to the bin directory
    cd ${ScriptPath}
    return 0
}
# end


# *****************configure syslog and kernlog**************************************
# Description:  configure syslog and kernlog
# ******************************************************************************
function configure_syslog_and_kernlog()
{
    if [ ! -d ${LogPath}squashfs-root/${MINIRC_LOGROTATE_DIR} ];then
        mkdir -p ${LogPath}squashfs-root/${MINIRC_LOGROTATE_DIR}
    fi

    echo "" > ${LogPath}squashfs-root/${MINIRC_LOGROTATE_DIR}minirc_logrotate
    echo "" > ${LogPath}squashfs-root/${MINIRC_LOGROTATE_DIR}minirc_logrotate.conf

    cat > ${LogPath}squashfs-root/${MINIRC_LOGROTATE_DIR}minirc_logrotate << EOF
#!/bin/bash

#Clean non existent log file entries from status file
cd /var/lib/logrotate
test -e status || touch status
head -1 status > status.clean
sed 's/"//g' status | while read logfile date
do
    [ -e "\${logfile}" ] && echo "\"\${logfile}\" \${date}"
done >> status.clean

test -x /usr/sbin/logrotate || exit 0
/usr/sbin/logrotate ${MINIRC_LOGROTATE_DIR}minirc_logrotate.conf
EOF

    cat > ${LogPath}squashfs-root/${MINIRC_LOGROTATE_DIR}minirc_logrotate.conf << EOF
# see "main logrotate" for details

# use the syslog group by default, since this is the owing group
# of /var/log/syslog.
su root syslog

# create new (empty) log files after rotating old ones
create
/var/log/syslog
{
        rotate ${SYSLOG_ROTATE}
        weekly
        maxsize ${SYSLOG_MAXSIZE}
        missingok
        notifempty
        compress
        postrotate
                invoke-rc.d rsyslog rotate > /dev/null
        endscript
}
/var/log/kern.log
{
        rotate ${SYSLOG_ROTATE}
        weekly
        maxsize ${SYSLOG_MAXSIZE}
        missingok
        notifempty
        compress
}
EOF
    chmod 755 ${LogPath}squashfs-root/${MINIRC_LOGROTATE_DIR}minirc_logrotate

    echo "*/30 *   * * *   root     cd / && run-parts --report ${MINIRC_LOGROTATE_DIR}" >> ${LogPath}squashfs-root/etc/crontab

    if [ -f ${LogPath}squashfs-root/etc/rsyslog.d/50-default.conf ];then
        sed -i 's/*.*;auth,authpriv.none/*.*;auth,authpriv,kern.none/g' ${LogPath}squashfs-root/etc/rsyslog.d/50-default.conf
    fi
    echo 'LogLevel=emerg' >> ${LogPath}squashfs-root/etc/systemd/system.conf
    echo 'MaxLevelStore=emerg' >> ${LogPath}squashfs-root/etc/systemd/journald.conf
    echo 'MaxLevelSyslog=emerg' >> ${LogPath}squashfs-root/etc/systemd/journald.conf
    echo 'MaxLevelKMsg=emerg' >> ${LogPath}squashfs-root/etc/systemd/journald.conf
    echo 'MaxLevelConsole=emerg' >> ${LogPath}squashfs-root/etc/systemd/journald.conf
    echo 'MaxLevelWall=emerg' >> ${LogPath}squashfs-root/etc/systemd/journald.conf
}


# ************************Configure ubuntu**************************************
# Description:  install ssh, configure user/ip and so on
# ******************************************************************************

# use vars to describe common commands
input_echo="
DRIVER_PACKAGE=\$1
username=\$2
usergroup=\$3
password=\$4
root_pwd=\$5
sys_user=\$6
sys_group=\$7
dm_user=\$8
dm_group=\$9
base_user=\${10}
base_group=\${11}
"
input_echo_1911=""
user_add_echo="
groupadd \${usergroup}
useradd -g \${usergroup} -m \${username} -d /home/\${username} -s /bin/bash
sed -i \"/^\${username}:/c\\\\\${password}\" /etc/shadow
sed -i \"/^root:/c\\\\\${root_pwd}\" /etc/shadow
groupadd  \${sys_group}
useradd  -g \${sys_group} -s /sbin/nologin -m \${sys_user}
groupadd  \${dm_group}
useradd  -g \${dm_group} -s /sbin/nologin -m \${dm_user}
groupadd  \${base_group}
useradd  -g \${base_group} -s /sbin/nologin -m \${base_user}
usermod -aG \${base_group} \${dm_user}
usermod -aG \${base_group} \${username}
usermod -aG \${usergroup} \${dm_user}
usermod -aG \${dm_group} \${username}
"
if [ "$FLAG_310B"x = "on"x ];then
input_echo_1911="
cp /lib/ld-linux-aarch64.so.1 /lib64/ld-linux-aarch64.so.1
chmod +x /lib/ld-linux-aarch64.so.1
chmod +x /lib64/ld-linux-aarch64.so.1
"
user_add_echo="
groupadd \${usergroup}
useradd -g \${usergroup} -m \${username} -d /home/\${username} -s /bin/bash
sed -i \"/^\${username}:/c\\\\\${password}\" /etc/shadow
sed -i \"/^root:/c\\\\\${root_pwd}\" /etc/shadow
groupadd -g 1100 \${sys_group}
useradd -u 1100 -g \${sys_group} -s /sbin/nologin -m \${sys_user}
groupadd -g 1101 \${dm_group}
useradd -u 1101 -g \${dm_group} -s /sbin/nologin -m \${dm_user}
groupadd -g 1102 \${base_group}
useradd -u 1102 -g \${base_group} -s /sbin/nologin -m \${base_user}
usermod -aG \${base_group} \${dm_user}
usermod -aG \${base_group} \${username}
usermod -aG \${usergroup} \${dm_user}
usermod -aG \${dm_group} \${username}
usermod -aG \${usergroup} \${base_user}
"
    if [ "$FAST_BOOT_FLAG"x == "on"x ];then
        ubuntu_disable_service_echo="
systemctl disable apport
systemctl disable cloud-config
systemctl disable cloud-final
systemctl disable cloud-init-local
systemctl disable cloud-init.service
systemctl disable cron.service
systemctl disable lvm2-monitor.service
systemctl disable multipathd.service
systemctl disable plymouth-start.service
systemctl mask plymouth-start.service
systemctl disable plymouth-quit-wait.service
systemctl mask plymouth-quit-wait.service
systemctl disable plymouth-quit.service
systemctl mask plymouth-quit.service
systemctl disable plymouth-read-write.service
systemctl mask plymouth-read-write.service
systemctl disable systemd-timesyncd.service
systemctl disable unattended-upgrades.service
systemctl disable systemd-networkd-wait-online.service
systemctl disable pollinate.service
rm -rf /usr/lib/systemd/system-generators/postfix-instance-generator
"
        openEuler_disable_service_echo="
systemctl disable multipathd.service
systemctl disable lm_sensors.service
systemctl disable plymouth-start.service
systemctl mask plymouth-start.service
systemctl disable plymouth-quit-wait.service
systemctl mask plymouth-quit-wait.service
systemctl disable plymouth-quit.service
systemctl mask plymouth-quit.service
systemctl disable plymouth-read-write.service
systemctl mask plymouth-read-write.service
systemctl disable systemd-timesyncd.service
"
    fi
fi

function configUbuntu()
{
    # 1. configure image sources
    mkdir -p ${LogPath}squashfs-root/cdtmp
    mount -o bind ${TMPDIR_DATE} ${LogPath}squashfs-root/cdtmp

    install_list=""
    if [ $DEV_NAME == "vdisk" ];then
        install_list="
apt-get install hwinfo -y
apt-get install smartmontools -y
apt-get install docker.io -y
"
        ifcfg_eth1="
echo \"$NETWORK_CONFIG_ETH1\" >> $NETWORK_CFG_FILE
"
    # delete usb0 network config
        ifcfg_usb0="
sed -i "11,15d" $NETWORK_CFG_FILE
"
    fi

    echo "
#!/bin/bash
${input_echo}
mkdir /lib64
${input_echo_1911}
# 1. apt install deb
mv /etc/apt/sources.list /etc/apt/sources.list.bak
touch /etc/apt/sources.list
echo \"deb file:/cdtmp ${ISO_SOURCE_VERSION}\" > /etc/apt/sources.list

locale-gen zh_CN.UTF-8 en_US.UTF-8 en_HK.UTF-8
apt-get update
echo \"make_sd_process: 5%\"
apt-get install openssh-server -y
apt-get install tar -y
apt-get install unzip -y
apt-get install vim -y
apt-get install zlib -y
apt-get install python2.7 -y
apt-get install python3 -y
apt-get install pciutils -y
echo \"make_sd_process: 10%\"
apt-get install nfs-common -y
apt-get install sysstat -y
apt-get install libelf1 -y
apt-get install libpython2.7 -y
apt-get install libnuma1 -y
apt-get install dmidecode -y
apt-get install rsync -y
apt-get install net-tools -y
echo \"make_sd_process: 20%\"
apt-get install psmisc -y
apt-get install sqlite3 -y
apt-get install parted -y
apt-get install arping -y
apt-get install ntpdate -y
apt-get install iputils-ping -y
apt-get install cracklib-runtime -y
apt-get install ethtool -y
apt-get install ntp -y
${install_list}
echo \"make_sd_process: 25%\"

mv /etc/apt/sources.list.bak /etc/apt/sources.list

# 2. set username
${user_add_echo}

# 3. config host
echo 'davinci-mini' > /etc/hostname
echo '127.0.0.1        localhost' > /etc/hosts
echo '127.0.1.1        davinci-mini' >> /etc/hosts

# 4. config ip
echo \"$NETWORK_CONFIG\" > $NETWORK_CFG_FILE
${ifcfg_eth1}
${ifcfg_usb0}

ln -sf /bin/bash /bin/sh
sed -i '/\/var\/log\/messages/ a\*.info;mail.none;authpriv.none;cron.none	\/var\/log\/messages' /etc/rsyslog.d/50-default.conf
sed -i 's/\$FileOwner syslog/#\$FileOwner syslog/g' /etc/rsyslog.conf
sed -i 's/\$FileGroup adm/#\$FileGroup adm/g' /etc/rsyslog.conf
sed -i 's/\$PrivDropToUser syslog/#\$PrivDropToUser syslog/g' /etc/rsyslog.conf
sed -i 's/\$PrivDropToGroup syslog/#\$PrivDropToGroup syslog/g' /etc/rsyslog.conf

# 5. auto-run minirc_cp.sh and minirc_sys_init.sh when start ubuntu
echo \"#!/bin/sh -e
#
# rc.local
#
# This script is executed at the end of each multiuser runlevel.
# Make sure that the script will \"exit 0\" on success or any other
# value on error.
#
# In order to enable or disable this script just change the execution
# bits.
#
# By default this script does nothing.
cd /var/


/bin/bash /var/minirc_boot.sh /opt/mini/${DRIVER_PACKAGE}

if [ -e /var/minirc_hook.sh ];then
    /bin/bash /var/minirc_hook.sh >>/var/minirc_hook.log
fi

if [ -f /etc/netplan/50-cloud-init.yaml ];then
    rm /etc/netplan/50-cloud-init.yaml
fi

if [ -f /lib/systemd/network/73-usb-net-by-mac.link ];then
    rm /lib/systemd/network/73-usb-net-by-mac.link
fi

systemctl restart rsyslog.service &
exit 0
\" > /etc/rc.local


chmod 755 /etc/rc.local
echo \"RuntimeMaxUse=50M\" >> /etc/systemd/journald.conf
echo \"SystemMaxUse=50M\" >> /etc/systemd/journald.conf

echo \"export LD_LIBRARY_PATH=/home/HwHiAiUser/Ascend/acllib/lib64\" >> /home/HwHiAiUser/.bashrc
echo \"/usr/lib64\" > /etc/ld.so.conf.d/mind_so.conf

sed -i '/^Subsystem/d' /etc/ssh/sshd_config
sed -i '/# override default of no subsystems/a\Subsystem    sftp  internal-sftp -l INFO -u 0077' /etc/ssh/sshd_config

#6. disable auto upgrade
echo \"APT::Periodic::Update-Package-Lists \\\"0\\\";
APT::Periodic::Unattended-Upgrade \\\"0\\\";
APT::Periodic::Download-Upgradeable-Packages \\\"0\\\";
APT::Periodic::AutocleanInterval \\\"0\\\";
\" > /etc/apt/apt.conf.d/20auto-upgrades

# 7. disbale service
${ubuntu_disable_service_echo}
exit
# end" > ${LogPath}squashfs-root/chroot_install.sh

    chmod 750 ${LogPath}squashfs-root/chroot_install.sh
    # 2. add user and install software
    # execute in ./chroot_install.sh

    chroot ${LogPath}squashfs-root /bin/bash -c "./chroot_install.sh ${DRIVER_PACKAGE} ${USER_NAME} ${USER_NAME} '"${USER_PWD}"' '"${ROOT_PWD}"' ${SYS_USER} ${SYS_USER} ${DM_USER} ${DM_USER} ${BASE_USER} ${BASE_USER}"

    if [[ $? -ne 0 ]];then
        echo "Failed: qemu is broken or the version of qemu is not compatible!"
        return 1;
    fi

    #configure syslog and kern log
    configure_syslog_and_kernlog

    umount ${LogPath}squashfs-root/cdtmp
    rm -rf ${LogPath}squashfs-root/cdtmp
    rm ${LogPath}squashfs-root/chroot_install.sh
    return 0
}

# end
# ************************Configure euler**************************************
# Description:  install ssh, configure user/ip and so on
# ******************************************************************************
function configEuler()
{
    # 1. configure image sources
    mkdir -p ${LogPath}squashfs-root/cdtmp
    mount -o bind /dev ${LogPath}squashfs-root/dev
    mount -o bind ${TMPDIR_DATE} ${LogPath}squashfs-root/cdtmp

    echo "
#!/bin/bash
${input_echo}

# 1. yum install rpm
#mv /etc/yum.repos.d/euler_local.repo /etc/yum.repos.d/euler_local.repo.back
touch /etc/yum.repos.d/euler_local.repo
echo \"
[euler-local]
name=euler
baseurl=file:///cdtmp
enable=1
gpgcheck=0\" > /etc/yum.repos.d/euler_local.repo

#locale-gen zh_CN.UTF-8 en_US.UTF-8 en_HK.UTF-8
yum update
echo \"make_sd_process: 5%\"
yum install openssh-server -y
yum install tar -y
yum install unzip -y
yum install vim -y
echo \"make_sd_process: 10%\"
yum install zlib -y
yum install python3 -y
yum install pciutils -y
yum install sysstat -y
echo \"make_sd_process: 20%\"
yum install dmidecode -y
yum install rsync -y
yum install net-tools -y
echo \"make_sd_process: 25%\"

#mv /etc/yum.repos.d/euler_local.repo.back /etc/yum.repos.d/euler_local.repo

# 2. set username
${user_add_echo}

# 3. config host
echo 'davinci-mini' > /etc/hostname
echo '127.0.0.1        localhost' > /etc/hosts
echo '127.0.1.1        davinci-mini' >> /etc/hosts

# 4. config ip
echo \"$NETWORK_CONFIG\" > $NETWORK_CFG_FILE

# 5. auto-run minirc_cp.sh and minirc_sys_init.sh when start system
echo \"#!/bin/sh -e
# rc.local
cd /var/

/bin/bash /var/minirc_boot.sh /opt/mini/${DRIVER_PACKAGE}

if [ -e /var/minirc_hook.sh ];then
     /bin/bash /var/minirc_hook.sh >>/var/minirc_hook.log
fi

exit 0
\" > /etc/rc.local
chmod 755 /etc/rc.local

# 6. enable su command default
sed -i '/pam_wheel/ s/^/#/' /etc/pam.d/su

echo \"RuntimeMaxUse=50M\" >> /etc/systemd/journald.conf
echo \"SystemMaxUse=50M\" >> /etc/systemd/journald.conf

echo \"export LD_LIBRARY_PATH=/home/HwHiAiUser/Ascend/acllib/lib64\" >> /home/HwHiAiUser/.bashrc

exit
# end" > ${LogPath}squashfs-root/chroot_install.sh

    chmod 750 ${LogPath}squashfs-root/chroot_install.sh
    # 2. add user and install software
    # execute in ./chroot_install.sh

    cat ${LogPath}squashfs-root/chroot_install.sh

    chroot ${LogPath}squashfs-root /bin/bash -c "./chroot_install.sh ${DRIVER_PACKAGE} ${USER_NAME} ${USER_NAME} '"${USER_PWD}"' '"${ROOT_PWD}"' ${SYS_USER} ${SYS_USER} ${DM_USER} ${DM_USER} ${BASE_USER} ${BASE_USER}"

    if [[ $? -ne 0 ]];then
        umount ${LogPath}squashfs-root/dev
        echo "Failed: qemu is broken or the version of qemu is not compatible!"
        return 1;
    fi

    #configure syslog and kern log
    configure_syslog_and_kernlog

    umount ${LogPath}squashfs-root/cdtmp
    umount ${LogPath}squashfs-root/dev
    rm -rf ${LogPath}squashfs-root/cdtmp
    rm -rf ${LogPath}squashfs-root/dev
    rm ${LogPath}squashfs-root/chroot_install.sh
    return 0
}

# ************************Configure openeuler**************************************
# Description:  install ssh, configure user/ip and so on
# ******************************************************************************
function configopenEuler()
{
    # 1. configure image sources
    mkdir -p ${LogPath}squashfs-root/cdtmp
    mount -o bind /dev ${LogPath}squashfs-root/dev
    mount -o bind ${TMPDIR_DATE} ${LogPath}squashfs-root/cdtmp

    install_list=""
    ifcfg_eth1=""
    if [ $DEV_NAME == "vdisk" ];then
        install_list="
dnf install hostname -y
dnf install parted -y
dnf install smartmontools -y
dnf install nfs-utils -y
dnf install cracklib -y
dnf install hwinfo -y
dnf install docker -y
"
        ifcfg_eth1="
touch /etc/sysconfig/network-scripts/ifcfg-eth1
echo \"$NETWORK_CONFIG_ETH1\" > /etc/sysconfig/network-scripts/ifcfg-eth1
touch /etc/sysconfig/network-scripts/ifcfg-usb0
echo \"$NETWORK_CONFIG_USB0\" > /etc/sysconfig/network-scripts/ifcfg-usb0
"
    fi

    echo "
#!/bin/bash
${input_echo}
${input_echo_1911}
# 1. dnf install rpm
mv /etc/yum.repos.d/openEuler.repo /etc/yum.repos.d/openEuler.repo.back
touch /etc/yum.repos.d/openEuler.repo
echo \"
[openeuler-local]
name=openeuler
baseurl=file:///cdtmp
enable=1
gpgcheck=0\" > /etc/yum.repos.d/openEuler.repo

#locale-gen zh_CN.UTF-8 en_US.UTF-8 en_HK.UTF-8
dnf update -y
echo \"make_sd_process: 5%\"
dnf install NetworkManager -y
dnf install passwd -y
dnf install sudo -y
dnf install openssh-server -y
dnf install tar -y
dnf install unzip -y
dnf install vim -y
echo \"make_sd_process: 10%\"
dnf install zlib -y
dnf install python3 -y
dnf install pciutils -y
dnf install sysstat -y
echo \"make_sd_process: 20%\"
dnf install dmidecode -y
dnf install rsync -y
dnf install net-tools -y
dnf install rsyslog -y
dnf install ethtool -y
dnf install usbutils -y
dnf install ntp -y
dnf install tpm2-abrmd -y
dnf install tpm2-tools -y
dnf install tpm2-tss -y
${install_list}
echo \"make_sd_process: 25%\"
mv /etc/yum.repos.d/openEuler.repo.back /etc/yum.repos.d/openEuler.repo

# 2. set username
${user_add_echo}

# 3. config host
echo 'davinci-mini' > /etc/hostname
echo '127.0.0.1        localhost' > /etc/hosts
echo '127.0.1.1        davinci-mini' >> /etc/hosts

# 4. config ip
mkdir /etc/sysconfig/network-scripts/
touch /etc/sysconfig/network-scripts/ifcfg-eth0
echo \"$NETWORK_CONFIG\" > $NETWORK_CFG_FILE
${ifcfg_eth1}
touch  /etc/resolv.conf

# 5. auto-run minirc_cp.sh and minirc_sys_init.sh when start system
echo \"#!/bin/sh -e
# rc.local
cd /var/
/bin/bash /var/minirc_boot.sh /opt/mini/${DRIVER_PACKAGE}
if [ -e /var/minirc_hook.sh ];then
     /bin/bash /var/minirc_hook.sh >>/var/minirc_hook.log
fi
exit 0
\" > /etc/rc.local
chmod 755 /etc/rc.local

# 6. enable su command default
sed -i '/pam_wheel/ s/^/#/' /etc/pam.d/su
echo \"RuntimeMaxUse=50M\" >> /etc/systemd/journald.conf
echo \"SystemMaxUse=50M\" >> /etc/systemd/journald.conf
echo \"export LD_LIBRARY_PATH=/home/HwHiAiUser/Ascend/acllib/lib64\" >> /home/HwHiAiUser/.bashrc
echo \"export LC_ALL=C.utf8\" >> /etc/profile
echo \"export LANG=C.utf8\" >> /etc/profile
sed -i '/^Subsystem/d' /etc/ssh/sshd_config
sed -i '/# override default of no subsystems/a\Subsystem    sftp  internal-sftp -l INFO -u 0077' /etc/ssh/sshd_config

systemctl disable plymouth-start.service
systemctl mask plymouth-start.service
systemctl disable plymouth-quit-wait.service
systemctl mask plymouth-quit-wait.service
systemctl disable plymouth-quit.service
systemctl mask plymouth-quit.service
systemctl disable plymouth-read-write.service
systemctl mask plymouth-read-write.service
systemctl disable multipathd.service
systemctl disable rngd.service

# 7. disbale service
${openEuler_disable_service_echo}
exit
# end" > ${LogPath}squashfs-root/chroot_install.sh
    chmod 750 ${LogPath}squashfs-root/chroot_install.sh
    # 2. add user and install software
    # execute in ./chroot_install.sh
    cat ${LogPath}squashfs-root/chroot_install.sh
    chroot ${LogPath}squashfs-root /bin/bash -c "./chroot_install.sh ${DRIVER_PACKAGE} ${USER_NAME} ${USER_NAME} '"${USER_PWD}"' '"${ROOT_PWD}"' ${SYS_USER} ${SYS_USER} ${DM_USER} ${DM_USER} ${BASE_USER} ${BASE_USER}"
    if [[ $? -ne 0 ]];then
        umount ${LogPath}squashfs-root/dev
        echo "Failed: qemu is broken or the version of qemu is not compatible!"
        return 1;
    fi

    #configure syslog and kern log
    configure_syslog_and_kernlog
    umount ${LogPath}squashfs-root/cdtmp
    umount ${LogPath}squashfs-root/dev
    rm -rf ${LogPath}squashfs-root/cdtmp
    rm -rf ${LogPath}squashfs-root/dev
    rm ${LogPath}squashfs-root/chroot_install.sh
    return 0
}

function configFilesystem()
{
    if [[ $ISO_FILE =~ "ubuntu" ]];then
        configUbuntu
        if [ $? -ne 0 ];then
            echo "Failed: config ubuntu fail!"
            return 1
        fi

        return 0
    elif [[ $ISO_FILE =~ "EulerOS" ]];then
        configEuler
        if [ $? -ne 0 ];then
            echo "Failed: config euleros fail!"
            return 1
        fi

        return 0
    elif [[ $ISO_FILE =~ "openEuler" ]];then
        configopenEuler
        if [ $? -ne 0 ];then
            echo "Failed: config openEuler fail!"
            return 1
        fi
        return 0
    else
        echo "Failed: unsupport os!"
        return 1
    fi
}

# ************************Format SDcard*****************************************
# Description:  format to ext3 filesystem and three partition
# ******************************************************************************
function delPartition()
{
    if [[ $(fdisk -l 2>/dev/null | grep "^${DEV_NAME}" | wc -l) -gt 1 ]];then
        for i in $(fdisk -l 2>/dev/null | grep "^${DEV_NAME}" | awk -F ' ' '{print $1}'); do
            echo "d

        w" | fdisk ${DEV_NAME}
    done
    else
        echo "d

    w" | fdisk ${DEV_NAME}
    fi
    umount ${DEV_NAME} 2>/dev/null
}

function formatSDcardFsBackup()
{
    delPartition

    sectorOffset_1M=$[1024*1024/sectorSize]
    sectorOffset1=$sectorOffset_1M
    # End1: rootfs_part_size + 1M - 1
    sectorEnd1=$[sectorOffset1+ROOT_PART_SIZE*sectorOffset_1M-1]
    # Offset2: rootfs_part_size + 1M
    sectorOffset2=$[sectorEnd1+1]
    # End2: rootfs_part_size + 1M - 1
    sectorEnd2=$[sectorOffset2+LOG_PART_SIZE*sectorOffset_1M-1]
    # Offset3: sectorEnd2 + 1
    sectorOffset3=$[sectorEnd2+1]
    # End3: sectorEnd - p4 size
    sectorEnd3=$[sectorEnd-ROOT_PART_SIZE*sectorOffset_1M]
    # Offset4: End3 + 1
    sectorOffset4=$[sectorEnd3+1]

    #verifying the capacity
    curSector=$[sectorEnd2+ROOT_PART_SIZE*sectorOffset_1M]
    if [ $curSector -ge $sectorEnd ]; then
        echo "Failed: SD/eMMC capacity is less than user Configuration, please reconfigure and make later"
        return 1
    fi

    echo "n
p
1
$sectorOffset1
$sectorEnd1
n
p
2
$sectorOffset2
$sectorEnd2
n
p
3
$sectorOffset3
$sectorEnd3
n
p
$sectorOffset4
$sectorEnd
w
" | fdisk ${DEV_NAME}

    partprobe

    fdisk -l

    sleep 5

    checkSDCard
    if [ $? -ne 0 ];then
        return 1
    fi
    echo "y
    " | mkfs.ext3 -L ubuntu_fs ${DEV_NAME}$p1
    if [[ $? -ne 0 ]];then
        echo "Failed: Format SDcard1 failed!"
        return 1;
    fi

    echo "make_sd_process: 30%"
    checkSDCard
    if [ $? -ne 0 ];then
        return 1
    fi
    echo "y
    " | mkfs.ext3 -L ubuntu_fs ${DEV_NAME}$p2
    if [[ $? -ne 0 ]];then
        echo "Failed: Format SDcard2 failed!"
        return 1;
    fi

    echo "make_sd_process: 35%"
    checkSDCard
    if [ $? -ne 0 ];then
        return 1
    fi
    echo "y
    " | mkfs.ext3 -L ubuntu_fs ${DEV_NAME}$p3
    if [[ $? -ne 0 ]];then
        echo "Failed: Format SDcard3 failed!"
        return 1;
    fi
    echo "make_sd_process: 45%"
    echo "y
    " | mkfs.ext3 -L ubuntu_fs ${DEV_NAME}$p4
    if [[ $? -ne 0 ]];then
        echo "Failed: Format SDcard4 failed!"
        return 1;
    fi
    return 0
}

# ************************Format SDcard*****************************************
# Description:  format to ext3 filesystem and three partition
# ******************************************************************************
function formatSDcard()
{
    delPartition

    sectorOffset_1M=$[1024*1024/sectorSize]
    sectorOffset1=$sectorOffset_1M
    # End1: rootfs_part_size + 1M - 1
    sectorEnd1=$[sectorOffset1+ROOT_PART_SIZE*sectorOffset_1M-1]
    # Offset2: rootfs_part_size + 1M
    sectorOffset2=$[sectorEnd1+1]
    # End2: rootfs_part_size + 1M - 1
    sectorEnd2=$[sectorOffset2+LOG_PART_SIZE*sectorOffset_1M-1]
    # Offset3: sectorEnd2 + 1
    sectorOffset3=$[sectorEnd2+1]

    #verifying the capacity
    curSector=$sectorEnd2
    if [ $curSector -ge $sectorEnd ]; then
        echo "Failed: SD/eMMC capacity is less than user Configuration, please reconfigure and make later"
        return 1
    fi

    echo "n
p
1
$sectorOffset1
$sectorEnd1
n
p
2
$sectorOffset2
$sectorEnd2
n
p
3
$sectorOffset3
$sectorEnd
w
" | fdisk ${DEV_NAME}

    partprobe

    fdisk -l

    sleep 5

    checkSDCard
    if [ $? -ne 0 ];then
        return 1
    fi
    echo "y
    " | mkfs.ext3 -L ubuntu_fs ${DEV_NAME}$p1
    if [[ $? -ne 0 ]];then
        echo "Failed: Format SDcard1 failed!"
        return 1;
    fi

    echo "make_sd_process: 30%"
    checkSDCard
    if [ $? -ne 0 ];then
        return 1
    fi
    echo "y
    " | mkfs.ext3 -L ubuntu_fs ${DEV_NAME}$p2
    if [[ $? -ne 0 ]];then
        echo "Failed: Format SDcard2 failed!"
        return 1;
    fi

    echo "make_sd_process: 35%"
    checkSDCard
    if [ $? -ne 0 ];then
        return 1
    fi
    echo "y
    " | mkfs.ext3 -L ubuntu_fs ${DEV_NAME}$p3
    if [[ $? -ne 0 ]];then
        echo "Failed: Format SDcard3 failed!"
        return 1;
    fi
    echo "make_sd_process: 45%"
    return 0
}

function DIYFormatSDcard()
{
    cnt=0
    #Five partitions are reserved.
    constPNum=5
    while read line
    do
        flag=`echo "$line" | awk -F "=" '{print $1}'`
        if [ "$flag"x == "OFFSIZE"x ];then
            offsize=`echo "$line" | awk '{print $1}' | awk -F "=" '{print $2}'`
            end=`echo "$line" | awk '{print $2}' | awk -F "=" '{print $2}'`
            if [[ "$offsize" -gt "0" ]] && [[ "$end" -gt "$offsize" ]];then
                DIYOffset=$[offsize*sectorOffset_1M]
                DIYEnd=$[end*sectorOffset_1M-1]
                if [[ $DIYEnd -ge $sectorEnd ]];then
                    echo "Failed: SD/eMMC capacity is less than user Configuration, please reconfigure and make later"
                    return 1;
                fi
                cnt=$[cnt+1]
                p_num=$[constPNum+cnt]

                add_list+=" mkpart p$p_num $DIYOffset$sectorUnit $DIYEnd$sectorUnit "
            fi
        fi
    done < ${MAKECONF}
}

function formatSDcard310B()
{
    sectorOffset_1M=$[1024*1024/sectorSize]
    #p1 need reserved 100M space
    sectorRsvP1=$[100*sectorOffset_1M]
    # End1:100M+784M-1
    sectorOffset1=$sectorRsv
    sectorEnd1=$[sectorRsvP1+sectorOffset1-1]
    # End2: rootfs_part_size + 884M - 1
    sectorOffset2=$[sectorEnd1+1]
    sectorEnd2=$[sectorOffset2+ROOT_PART_SIZE*sectorOffset_1M-1]
    # End3: rootfs_part_size*2 + 884M - 1
    sectorOffset3=$[sectorEnd2+1]
    sectorEnd3=$[sectorOffset3+ROOT_PART_SIZE*sectorOffset_1M-1]
    if [ "$FS_BACKUP_FLAG"x = "off"x ];then
        #reserved 100M space for p3
        sectorEnd3=$[sectorOffset3+100*sectorOffset_1M-1]
    fi
    # End4: rootfs_part_size + p3 + HOME_DATA_SIZE + 884M - 1
    sectorOffset4=$[sectorEnd3+1]
    sectorEnd4=$[sectorOffset4+HOME_DATA_SIZE*sectorOffset_1M-1]
    # End5: rootfs_part_size + p3 + HOME_DATA_SIZE + LOG_PART_SIZE + 884M - 1
    sectorOffset5=$[sectorEnd4+1]
    sectorEnd5=$[sectorOffset5+LOG_PART_SIZE*sectorOffset_1M-1]

    sectorUnit="s"
    parted $DEV_NAME -s mklabel gpt
    ex_p_n=`parted $DEV_NAME -s p | sed -n '/p2/,$p' | awk '{print $1}'`
    for i in $ex_p_n
    do
        rm_list+="rm ${i}"
    done
    echo rm_list: ${rm_list}
    add_list+="mkpart p1 $sectorOffset1$sectorUnit $sectorEnd1$sectorUnit "
    add_list+="mkpart p2 $sectorOffset2$sectorUnit $sectorEnd2$sectorUnit "
    add_list+="mkpart p3 $sectorOffset3$sectorUnit $sectorEnd3$sectorUnit "
    add_list+="mkpart p4 $sectorOffset4$sectorUnit $sectorEnd4$sectorUnit "
    add_list+="mkpart p5 $sectorOffset5$sectorUnit $sectorEnd5$sectorUnit "

    DIYFormatSDcard
    echo add_list: ${add_list}
    parted $DEV_NAME -s ${rm_list} ${add_list}
    ret=$?
    if [ $ret -ne 0 ];then
        echo "Failed: parted $DEV_NAME -s ${rm_list} ${add_list} failed !"
        return 1
    fi
    ext4_list=`parted $DEV_NAME -s p | sed -n '/p2/,$p' | awk '{print $1}'`
    for i in $ext4_list
    do
        mkfs.ext4 -F $DEV_NAME${i}
        if [[ $? -ne 0 ]];then
            echo "Failed: Format SDcard${i} failed!"
            return 1;
        fi
    done
}

function mkMountDir()
{
    local mount_name="$1"
    local partitionum="$2"
    if [[ -d "${mount_name}" ]];then
        umount ${mount_name} 2>/dev/null
        rm -rf ${mount_name}
    fi
    mkdir ${mount_name}
    mount ${DEV_NAME}$partitionum ${mount_name} 2>/dev/null
}

function configSDcard()
{
    if [ "$FLAG_310B"x = "on"x ];then
        if [ $MAKE_IMGPK_FLAG = "on" ];then
            return 0
        fi
        formatSDcard310B || return 1

    else
        if [ "$FS_BACKUP_FLAG"x = "on"x ]; then
            formatSDcardFsBackup || return 1
        else
            formatSDcard || return 1
        fi
    fi
    if [ "$FLAG_310B"x = "on"x ];then
        #310B fs partition is start at p2
        mkMountDir ${TMPDIR_SD_MOUNT} $p2
        if [ "$FS_BACKUP_FLAG"x = "on"x ]; then
            mkMountDir ${TMPDIR_SD2_MOUNT} $p3
        fi
        mkMountDir ${TMPDIR_SD3_MOUNT} $p4
        echo "make_sd_process: 50%"
        mkMountDir ${TMPDIR_SD4_MOUNT} $p5
    else
        mkMountDir ${TMPDIR_SD_MOUNT} $p1
        mkMountDir ${TMPDIR_SD2_MOUNT} $p2
        echo "make_sd_process: 50%"
        mkMountDir ${TMPDIR_SD3_MOUNT} $p3

        if [ "$FS_BACKUP_FLAG"x = "on"x ]; then
            mkMountDir ${TMPDIR_SD4_MOUNT} $p4
        fi
    fi
    echo "make_sd_process: 55%"
}
#end

# ************************Copy files to SD**************************************
# Description:  copy rar and root filesystem to SDcard
# ******************************************************************************
function preInstallDriver()
{
    echo "start pre install driver"
	mkdir -p ${LogPath}squashfs-root/opt/mini
    chmod 755 ${LogPath}squashfs-root/opt/mini

    # 1. copy third party file
    tar zxf ${ISO_FILE_DIR}/${DRIVER_PACKAGE} -C ${LogPath} driver/scripts/minirc_install_phase1.sh
    cp ${LogPath}driver/scripts/minirc_install_phase1.sh ${LogPath}squashfs-root/opt/mini/
    if [[ $? -ne 0 ]];then
        echo "Failed: Copy minirc_install_phase1.sh to filesystem failed!"
        return 1
    fi
    chmod +x ${LogPath}/driver/scripts/minirc_install_phase1.sh

    echo "make_sd_process: 75%"

    tar -zxf ${ISO_FILE_DIR}/${DRIVER_PACKAGE} -C ${LogPath} driver/scripts/minirc_boot.sh
    cp ${LogPath}driver/scripts/minirc_boot.sh ${LogPath}squashfs-root/var/
    if [[ $? -ne 0 ]];then
        echo "Failed: Copy minirc_boot.sh to filesystem failed!"
        return 1
    fi

    echo "make_sd_process: 80%"
    # 2. copy root filesystem
    if [[ ${arch} =~ "x86" ]];then
        rm ${LogPath}squashfs-root/usr/bin/qemu-aarch64-static
    fi

    #install $DRIVER_PACKAGE
    mkdir -p ${LogPath}mini_pkg_install/opt/mini
    cp ${ISO_FILE_DIR}/${DRIVER_PACKAGE}  ${LogPath}mini_pkg_install/opt/mini/
    chmod +x ${LogPath}squashfs-root/opt/mini/minirc_install_phase1.sh
    ${LogPath}driver/scripts/minirc_install_phase1.sh ${LogPath}mini_pkg_install
    res=$(echo $?)
    if [[ ${res} != "0" ]];then
        echo "Install ${DRIVER_PACKAGE} fail, error code:${res}"
        echo "Failed: Install ${DRIVER_PACKAGE} failed!"
        return 1
    fi

}

function copyFilesToSDcard()
{
    cp -a ${LogPath}squashfs-root/* ${TMPDIR_SD_MOUNT}
    if [[ $? -ne 0 ]];then
        echo "Failed: Copy root filesystem to SDcard failed!"
        return 1
    fi

    if [ "$FS_BACKUP_FLAG"x = "on"x ]; then
        cp -a ${LogPath}squashfs-root/* ${TMPDIR_SD4_MOUNT}
        if [[ $? -ne 0 ]];then
            echo "Failed: Copy root filesystem to backup SDcard failed!"
            return 1
        fi
    fi

    cp -rf ${TMPDIR_SD_MOUNT}/home/* ${TMPDIR_SD3_MOUNT}/

    cp -rf ${TMPDIR_SD_MOUNT}/var/log/* ${TMPDIR_SD2_MOUNT}/
    echo "make_sd_process: 90%"
    return 0
}

function preInstallHook()
{
    if [ -e "${ScriptPath}/minirc_install_hook.sh" ];then
        bash ${ScriptPath}/minirc_install_hook.sh "${LogPath}squashfs-root/"
        if [ $? -ne 0 ];then
            echo "Excute minirc_install_hook.sh failed"
            return 1
        else
            echo "Excute minirc_install_hook.sh success"
        fi
    fi
    return 0
}

function preInstallMinircPackage()
{
    preInstallDriver
    if [ $? -ne 0 ];then
        echo "Pre install driver package failed"
        return 1
    fi

    preInstallHook
    if [ $? -ne 0 ];then
        return 1
    fi

    rm -rf ${LogPath}mini_pkg_install/opt
    cp -rf ${LogPath}mini_pkg_install/* ${LogPath}squashfs-root/
    if [[ $? -ne 0 ]];then
        echo "Failed: Copy mini_pkg_install to filesystem failed!"
        return 1
    fi
    echo "pre install drvier finished"
    echo "make_sd_process: 85%"
    rm -rf ${LogPath}mini_pkg_install

    copyFilesToSDcard
    if [ $? -ne 0 ];then
        echo "Copy file to sdcard failed"
        return 1
    fi
}

function mkInstallInfo()
{
    Driver_Install_Path_Param="/var/davinci"
    Driver_Install_For_All="no"
    Driver_Install_Mode="normal"
    Driver_Install_Type="full"
    echo "UserName=HwHiAiUser
UserGroup=HwHiAiUser
Driver_Install_Path_Param=$Driver_Install_Path_Param
Driver_Install_For_All=$Driver_Install_For_All
Driver_Install_Mode=$Driver_Install_Mode
Driver_Install_Type=$Driver_Install_Type" > ${LogPath}squashfs-root/etc/ascend_install.info
}

function setStartDavinciService()
{
    mkdir -p ${LogPath}squashfs-root/usr/local/scripts/
    cp $Install_Cache_Path_Param/scripts/start_davinci.sh ${LogPath}squashfs-root/usr/local/scripts/
    cp $Install_Cache_Path_Param/scripts/start-davinci.service ${LogPath}squashfs-root/usr/lib/systemd/system/

    echo "
#!/bin/bash

chown -h root:root /usr/local/scripts/start_davinci.sh
chmod 500 /usr/local/scripts/start_davinci.sh
chown -h root:root /usr/lib/systemd/system/start-davinci.service
chmod 600 /usr/lib/systemd/system/start-davinci.service
cd /etc/systemd/system/multi-user.target.wants/
ln -sf /usr/lib/systemd/system/start-davinci.service  start-davinci.service

chmod 550 /var/minirc_boot.sh
chmod 644 /etc/ascend_install.info
echo \"/bin/bash /var/minirc_boot.sh /var/Ascend/${DRIVER_PACKAGE}\" >> /usr/local/scripts/start_davinci.sh
sed -i --follow-symlinks 's/\/bin\/bash \/var\/minirc_boot.sh \/opt\/mini\/${DRIVER_PACKAGE}//' /etc/rc.local

if [ ! -e /dev/null ]; then
    mkdir /dev
    mknod -m 666 /dev/null c 1 3
fi
cat /etc/os-release | grep \"Ubuntu\" 2> /dev/null
ret=$?
if [ $ret -eq 0 ];then
    systemctl disable cloud-init-local.service
    systemctl disable cloud-init.service
    systemctl disable cloud-config.service
    systemctl disable cloud-final.service

    apt purge cloud-init -y
fi
" > ${LogPath}squashfs-root/service_config.sh

    if [ "$FS_BACKUP_FLAG"x = "on"x ] || ([ "$MAKE_IMGPK_FLAG"x = "on"x ] && [ "$FAST_BOOT_FLAG"x = "off"x ]); then
        if [ ! -f ${ScriptPath}tools/inotifywait ];then
            echo "Failed: There is no inotify tool !"
            return 1
        fi
        cp ${ScriptPath}tools/inotifywait ${LogPath}squashfs-root/usr/sbin/
        cp ${ScriptPath}synctool/* ${LogPath}squashfs-root/usr/local/scripts/
        echo "
[Unit]
Description=etc file resume
DefaultDependencies=no
# systemd-udevd.service can be dropped once tuntap is moved to netlink
After=home-data.mount
Before=local-fs.target start-davinci.service
Conflicts=shutdown.target

[Service]
Type=forking
ExecStart=/usr/local/scripts/etc_resume.sh
StandardOutput=syslog
StandardError=inherit

[Install]
WantedBy=multi-user.target
" > ${LogPath}squashfs-root/usr/lib/systemd/system/etc-resume.service
        echo "
[Unit]
Description=devm_drv_init
After=network-online.target firewalld.service start-davinci.service
Before=docker.service
Wants=network-online.target

[Service]
Type=forking
ExecStart=/usr/local/scripts/devm_drv_init.sh
TimeoutSec=6000

[Install]
WantedBy=multi-user.target
" > ${LogPath}squashfs-root/usr/lib/systemd/system/devm_drv_init.service
        echo "
chmod 755 /usr/sbin/inotifywait
chown -h root:root /usr/local/scripts/config_resume.sh
chmod 500 /usr/local/scripts/config_resume.sh
chown -h root:root /usr/local/scripts/etc_backup.sh
chmod 500 /usr/local/scripts/etc_backup.sh
chown -h root:root /usr/local/scripts/etc_resume.sh
chmod 500 /usr/local/scripts/etc_resume.sh
chown -h root:root /usr/local/scripts/devm_log_print.sh
chmod 500 /usr/local/scripts/devm_log_print.sh
chown -h root:root /usr/local/scripts/upgrade_drv.sh
chmod 500 /usr/local/scripts/upgrade_drv.sh
chown -h root:root /usr/local/scripts/devm_drv_init.sh
chmod 500 /usr/local/scripts/devm_drv_init.sh

chown -h root:root /usr/lib/systemd/system/etc-resume.service
chmod 600 /usr/lib/systemd/system/etc-resume.service
chown -h root:root /usr/lib/systemd/system/devm_drv_init.service
chmod 600 /usr/lib/systemd/system/devm_drv_init.service
cd /etc/systemd/system/multi-user.target.wants/
ln -sf /usr/lib/systemd/system/etc-resume.service  etc-resume.service
ln -sf /usr/lib/systemd/system/devm_drv_init.service  devm_drv_init.service
" >> ${LogPath}squashfs-root/service_config.sh
    fi
    chmod 750 ${LogPath}squashfs-root/service_config.sh
    chroot ${LogPath}squashfs-root /bin/bash -c "./service_config.sh"
    if [[ $? -ne 0 ]];then
        echo "Failed: qemu is broken or the version of qemu is not compatible!"
        return 1;
    fi

    rm -f ${LogPath}squashfs-root/service_config.sh
}

function configFstab()
{
    mkdir -p ${LogPath}squashfs-root/home/log
    mkdir -p ${LogPath}squashfs-root/home/data
    if [ $MAKE_IMGPK_FLAG == "on" ];then
        if [ "$CARD_TYPE"x == "eMMC"x ];then
            boot_dev="mmcblk0"
        elif [ "$CARD_TYPE"x == "SD"x ];then
            boot_dev="mmcblk1"
        fi
        echo "
# <file system>    <mount point>     <type>  <options>       <dump>  <pass>
/dev/${boot_dev}p4      /home/data        ext4    defaults        0       0
/dev/${boot_dev}p5      /home/log         ext4    defaults        0       0
/dev/${boot_dev}p6      /usr/local/mindx  ext4    defaults        0       0
/dev/${boot_dev}p7      /home/package     ext4    defaults        0       0
tmpfs      /var/log       tmpfs    rw,mode=0755,size=128M     0       0
" > ${LogPath}squashfs-root/etc/fstab
        mkdir -p ${LogPath}squashfs-root/home/package
        mkdir -p ${LogPath}squashfs-root/usr/local/mindx
        return 0
    fi

    if [ "$CARD_TYPE"x == "M.2"x ] || [ "$CARD_TYPE"x == "NVME"x ];then
        uuid4=`blkid ${DEV_NAME}${suffix}4 -s PARTUUID | awk -F ' ' '{print $2}' | sed 's/\"//g'`
        uuid5=`blkid ${DEV_NAME}${suffix}5 -s PARTUUID | awk -F ' ' '{print $2}' | sed 's/\"//g'`
        echo "
# <file system>    <mount point>   <type>  <options>       <dump>  <pass>
${uuid4}      /home/data      ext4    defaults        0       0
${uuid5}      /home/log       ext4    defaults        0       0
tmpfs      /var/log       tmpfs    rw,mode=0755,size=128M   0       0
" > ${LogPath}squashfs-root/etc/fstab
    else
        echo "
# <file system>    <mount point>   <type>  <options>       <dump>  <pass>
/dev/mmcblk1p4      /home/data      ext4    defaults        0       0
/dev/mmcblk1p5      /home/log       ext4    defaults        0       0
tmpfs      /var/log       tmpfs    rw,mode=0755,size=128M   0       0
" > ${LogPath}squashfs-root/etc/fstab
    fi
}

function config310BJournald()
{
    cat ${LogPath}squashfs-root/etc/os-release | grep "openEuler" 2> /dev/null
    ret=$?
    if [ $ret -eq 0 ];then
        jourPath="${LogPath}squashfs-root/etc/systemd/journald.conf"
        sed -i 's/MaxLevelStore=emerg/#MaxLevelStore=debug/' $jourPath
        sed -i 's/MaxLevelSyslog=emerg/#MaxLevelSyslog=debug/' $jourPath
        sed -i 's/MaxLevelKMsg=emerg/#MaxLevelKMsg=notice/' $jourPath
        sed -i 's/MaxLevelConsole=emerg/#MaxLevelConsole=info/' $jourPath
        sed -i 's/MaxLevelWall=emerg/#MaxLevelWall=emerg/' $jourPath
    fi
}

function config310BLogind()
{
    cat ${LogPath}squashfs-root/etc/os-release | grep "ubuntu" 2> /dev/null
    ret=$?
    if [ $ret -eq 0 ];then
        logindPath="${LogPath}squashfs-root/etc/systemd/logind.conf"
        sed -i 's/#RemoveIPC=yes/RemoveIPC=no/' $logindPath
    fi
}

function config310BforUbuntuSshdKeyGen()
{
    cat ${LogPath}squashfs-root/etc/os-release | grep "Ubuntu" 2> /dev/null
    ret=$?
    if [ $ret -eq 0 ];then
        echo "
[Unit]
Description=OpenSSH %i Server Key Generation
ConditionFileNotEmpty=|!/etc/ssh/ssh_host_%i_key

[Service]
Type=oneshot
EnvironmentFile=-/etc/sysconfig/sshd
ExecStart=/usr/lib/openssh/sshd-keygen %i

[Install]
WantedBy=sshd-keygen.target
" > ${LogPath}squashfs-root/usr/lib/systemd/system/sshd-keygen@.service
        echo "
[Unit]
Wants=sshd-keygen@rsa.service
Wants=sshd-keygen@ecdsa.service
Wants=sshd-keygen@ed25519.service
PartOf=sshd.service
" > ${LogPath}squashfs-root/usr/lib/systemd/system/sshd-keygen.target
        echo "#!/bin/bash

# Create the host keys for the OpenSSH server.
KEYTYPE=\$1
case \$KEYTYPE in
	\"dsa\") ;& # disabled in FIPS
	\"ed25519\")
		FIPS=/proc/sys/crypto/fips_enabled
		if [[ -r \"\$FIPS\" && \$(cat \$FIPS) == \"1\" ]]; then
			exit 0
		fi ;;
	\"rsa\") ;; # always ok
	\"ecdsa\") ;;
	*) # wrong argument
		exit 12 ;;
esac
KEY=/etc/ssh/ssh_host_\${KEYTYPE}_key

KEYGEN=/usr/bin/ssh-keygen
if [[ ! -x \$KEYGEN ]]; then
	exit 13
fi

# remove old keys
rm -f \$KEY{,.pub}

# create new keys
if ! \$KEYGEN -q -t \$KEYTYPE -f \$KEY -C '' -N '' >&/dev/null; then
	exit 1
fi

# sanitize permissions
/usr/bin/chmod 400 \$KEY
/usr/bin/chmod 400 \$KEY.pub
if [[ -x /usr/sbin/restorecon ]]; then
	/usr/sbin/restorecon \$KEY{,.pub}
fi

exit 0
" > ${LogPath}squashfs-root/usr/lib/openssh/sshd-keygen

chmod 755 ${LogPath}squashfs-root/usr/lib/openssh/sshd-keygen

sed -i 's/auditd.service/& sshd-keygen.target/' ${LogPath}squashfs-root/usr/lib/systemd/system/ssh.service
sed -i '/^ConditionPathExists/i Wants=sshd-keygen.target' ${LogPath}squashfs-root/usr/lib/systemd/system/ssh.service
rm -rf  ${LogPath}squashfs-root/etc/systemd/system/ssh*
cd  ${LogPath}squashfs-root/etc/systemd/system/
ln -sf /lib/systemd/system/ssh.service sshd.service
cd -
    fi
}

function updateStructInfo()
{
    if [ ! -f ${ScriptPath}emmc-head ];then
        echo "failed: emmctool no exist"
        return 1
    fi

    if [ $MAKE_IMGPK_FLAG = "on" ];then
        if [ "$CARD_TYPE"x == "eMMC"x ];then
            boot_dev="mmcblk0"
        elif [ "$CARD_TYPE"x == "SD"x ];then
            boot_dev="mmcblk1"
        fi
        ${ScriptPath}emmc-head $Install_Cache_Path_Param/firmware/ /dev/${boot_dev}p2 /dev/${boot_dev}p3 force_recover
        if [[ $? -ne 0 ]];then
            return 1
        fi
        return 0
    fi

    if [ "$CARD_TYPE"x == "M.2"x ] || [ "$CARD_TYPE"x == "NVME"x ];then
        uuid2=`blkid ${DEV_NAME}${suffix}2 -s PARTUUID | awk -F ' ' '{print $2}' | sed 's/\"//g'`
        uuid3=`blkid ${DEV_NAME}${suffix}3 -s PARTUUID | awk -F ' ' '{print $2}' | sed 's/\"//g'`
        ${ScriptPath}emmc-head $Install_Cache_Path_Param/firmware/ ${uuid2} ${uuid2}
        if [[ $? -ne 0 ]];then
            return 1
        fi
        if [ "$FS_BACKUP_FLAG"x = "on"x ]; then
            ${ScriptPath}emmc-head $Install_Cache_Path_Param/firmware/ ${uuid2} ${uuid3}
            if [[ $? -ne 0 ]];then
                return 1
            fi
        fi
    elif [ "$CARD_TYPE"x == "USB"x ];then
        mv $Install_Cache_Path_Param/firmware/initrd $Install_Cache_Path_Param/firmware/initrd.bak
        cp -rf ${ScriptPath}initrd_usb $Install_Cache_Path_Param/firmware/initrd
        cp -rf ${ScriptPath}initrd_usb $Install_Cache_Path_Param/firmware/
        sed -i 's/BURN_IMAGE_FLAG=off/BURN_IMAGE_FLAG=on/' ${ScriptPath}mksd.conf
        ${ScriptPath}emmc-head $Install_Cache_Path_Param/firmware/ /dev/mmcblk1p2 /dev/mmcblk1p2
        if [[ $? -ne 0 ]];then
            return 1
        fi
        if [ "$FS_BACKUP_FLAG"x = "on"x ]; then
            ${ScriptPath}emmc-head $Install_Cache_Path_Param/firmware/ /dev/mmcblk1p2 /dev/mmcblk1p3
            if [[ $? -ne 0 ]];then
                return 1
            fi
        fi
        sed -i 's/BURN_IMAGE_FLAG=on/BURN_IMAGE_FLAG=off/' ${ScriptPath}mksd.conf
        mv $Install_Cache_Path_Param/firmware/initrd.bak $Install_Cache_Path_Param/firmware/initrd
    else
        ${ScriptPath}emmc-head $Install_Cache_Path_Param/firmware/ /dev/mmcblk1p2 /dev/mmcblk1p2
        if [[ $? -ne 0 ]];then
            return 1
        fi
        if [ "$FS_BACKUP_FLAG"x = "on"x ]; then
            ${ScriptPath}emmc-head $Install_Cache_Path_Param/firmware/ /dev/mmcblk1p2 /dev/mmcblk1p3
            if [[ $? -ne 0 ]];then
                return 1
            fi
        fi
    fi
}

function preInstallMinirc310BPackage()
{
    #preinstall driver
    echo "start pre install driver"
    Install_Cache_Path_Param="/var/Ascend/install_cache"
    bash ${ISO_FILE_DIR}/${DRIVER_PACKAGE} --noexec --extract=$Install_Cache_Path_Param
    res=$(echo $?)
    if [[ ${res} != "0" ]];then
        echo "Install ${DRIVER_PACKAGE} fail, error code:${res}"
        echo "Failed: Install ${DRIVER_PACKAGE} failed!"
        return 1
    fi
    updateStructInfo
    if [[ $? -ne 0 ]];then
        echo "Failed: Update struct info failed!"
        return 1
    fi
    cp $Install_Cache_Path_Param/scripts/minirc_boot.sh ${LogPath}squashfs-root/var/
    if [[ $? -ne 0 ]];then
        echo "Failed: Copy minirc_boot.sh to filesystem failed!"
        return 1
    fi
    mkInstallInfo
    setStartDavinciService
    configFstab
    config310BJournald
    config310BforUbuntuSshdKeyGen
    config310BLogind

    tar --no-same-owner -xvf ${Install_Cache_Path_Param}/modules.tar.gz -C ${LogPath}squashfs-root/lib/modules/ >/dev/null 2>&1
    mkdir -p ${LogPath}squashfs-root/var/Ascend/install_cache
    cp -rf $Install_Cache_Path_Param/* ${LogPath}squashfs-root/var/Ascend/install_cache/
    if [[ $? -ne 0 ]];then
        echo "Failed: Copy install_cache_files to filesystem failed!"
        return 1
    fi
    mkdir -p ${LogPath}squashfs-root/fw
    cp $Install_Cache_Path_Param/firmware/* ${LogPath}squashfs-root/fw/
    if [[ $? -ne 0 ]];then
        echo "Failed: Copy firmware to filesystem failed!"
        return 1
    fi
    echo "pre install drvier finished"
    echo "make_sd_process: 85%"
    if [[ ${arch} =~ "x86" ]];then
        rm ${LogPath}squashfs-root/usr/bin/qemu-aarch64-static
    fi

    #when user want use custom scripts
    preInstallHook
    if [ $? -ne 0 ];then
        return 1
    fi

    #copyFiles
    #recover mode has no mount dir, cannot cp files to sd
    if [ $MAKE_IMGPK_FLAG = "on" ];then
        return 0
    fi
    cp -a ${LogPath}squashfs-root/* ${TMPDIR_SD_MOUNT}
    if [[ $? -ne 0 ]];then
        echo "Failed: Copy root filesystem to SDcard failed!"
        return 1
    fi

    if [ "$FS_BACKUP_FLAG"x = "on"x ]; then
        cp -a ${LogPath}squashfs-root/* ${TMPDIR_SD2_MOUNT}
        if [[ $? -ne 0 ]];then
            echo "Failed: Copy root filesystem to backup SDcard failed!"
            return 1
        fi
    fi
    echo "make_sd_process: 90%"
    return 0
}

function copyRecoverFile()
{
    #cp filesystem
    cd ${LogPath}squashfs-root
    if [ "$CARD_TYPE"x == "M.2"x ] || [ "$CARD_TYPE"x == "NVME"x ]; then
        if [ -e "etc/lsb-release" ] && grep -q "Ubuntu" etc/lsb-release; then
            echo "wheel:x:10:" >> etc/group
            sed -i 's/^uucp:x:10:/uucp:x:11:/' etc/group
            sed -i 's/uucp:x:10:10:uucp:\/var\/spool\/uucp:\/usr\/sbin\/nologin/uucp:x:10:11:uucp:\/var\/spool\/uucp:\/usr\/sbin\/nologin/g' etc/passwd
        fi

        if [ -e "etc/openEuler-release" ]; then
            sed -i "/^root:/croot:x:0:0:root:\/root:\/bin\/bash" etc/passwd
        fi

        chroot ./ useradd admin -d /home/admin -m -s /usr/local/bin/clp -u 1202 -g 10
        chroot ./ sed -i "/^admin:/c${ADMIN_PWD}" /etc/shadow
        chroot ./ passwd -e admin
    fi
    chroot ./ mkdir -p /home/HwHiAiUser/hdc_ppc
    chroot ./ chown HwHiAiUser:HwHiAiUser /home/HwHiAiUser/hdc_ppc
    chroot ./ chmod 750 /home/HwHiAiUser/hdc_ppc
    chroot ./ passwd -e root
    chroot ./ passwd -e HwHiAiUser
    find . | cpio -o -H newc | gzip > ${LogPath}/os.img
    if [ $? -ne 0 ];then
        echo "Failed: cpio/gzip new initrd failed!"
        return 1
    fi
    cp ${LogPath}/os.img ${LogPath}recoverMntdir
    if [ $? -ne 0 ];then
        echo "Falied: copy new initrd to virtual disk failed!"
        return 1
    fi
    cd ${LogPath}recoverMntdir
    tar zcvf A500-A2-os.tar.gz os.img
    rm -f os.img
    #cp tools
    cp $Install_Cache_Path_Param/drv_mem_ctrl.ko ${LogPath}recoverMntdir
    cp $Install_Cache_Path_Param/sbsa_gwdt.ko ${LogPath}recoverMntdir
    cp $Install_Cache_Path_Param/boot_tool ${LogPath}recoverMntdir
    cp $Install_Cache_Path_Param/scripts/restore_factory.sh ${LogPath}recoverMntdir
    cp $Install_Cache_Path_Param/scripts/restore_factory_common.sh ${LogPath}recoverMntdir
    cp $Install_Cache_Path_Param/scripts/reset_rootfs.sh ${LogPath}recoverMntdir
    cp $Install_Cache_Path_Param/scripts/reset_npu_drv.sh ${LogPath}recoverMntdir

    cp ${pk_driver} ${LogPath}recoverMntdir
    cp ${pk_mefedge} ${LogPath}recoverMntdir
    cp ${pk_om} ${LogPath}recoverMntdir
    cp ${pk_toolbox} ${LogPath}recoverMntdir
    cp ${pk_cann} ${LogPath}recoverMntdir

    tar zxf ${pk_om} -C ${recoverfilepath} scripts/reset_om.sh
    tar zxf ${pk_mefedge} -C ${recoverfilepath} software/edge_installer/script/reset_middleware.sh

    cp ${recoverfilepath}/scripts/reset_om.sh ${LogPath}recoverMntdir
    cp ${recoverfilepath}/software/edge_installer/script/reset_middleware.sh ${LogPath}recoverMntdir
    if [ "$CARD_TYPE"x == "M.2"x ] || [ "$CARD_TYPE"x == "NVME"x ]; then
        cp ${pk_hdm} ${LogPath}recoverMntdir
        tar zxf ${pk_hdm} -C ${recoverfilepath} usr/local/scripts/reset_hdm.sh
        cp ${recoverfilepath}/usr/local/scripts/reset_hdm.sh ${LogPath}recoverMntdir
        cp ${ScriptPath}emmc-head ${LogPath}recoverMntdir
    fi

    if [ -n "${pk_user_defined}" ]; then
        cp ${pk_user_defined} ${LogPath}recoverMntdir
        cp ${recoverfilepath}/reset_user_defined_files.sh ${LogPath}recoverMntdir
    fi

    #support user-defined scripts
    if [ -f ${recoverfilepath}/restore_factory.sh ];then
        cp -f ${recoverfilepath}/restore_factory.sh ${LogPath}recoverMntdir
        echo "Find recovertool/restore_factory.sh , use user-defined scripts."
    fi
    rm -rf ${recoverfilepath}/scripts
    rm -rf ${recoverfilepath}/software
    cd ${ScriptPath}
}

function makeInitrdImg()
{
    vdisk="recoverfs-${OS_TYPE}-${CARD_TYPE}.img"
    #2320Mb=4751360sector
    #784Mb=1605632sector
    dd if=/dev/zero of=$vdisk bs=512 count=4751360
    if [ $? -ne 0 ];then
        echo "Failed: make virtual disk failed!"
        return 1
    fi

    parted $vdisk -s mklabel gpt
    parted $vdisk -s mkpart p1 1605632s 4751326s
    #losetup can make file a block device, kpartx make it can be mounted
    loopdevice=$(losetup -f --show $vdisk)
    device=`kpartx -va $loopdevice | awk -F " " '{print $3}'`
    partRecover="/dev/mapper/${device}"
    mkfs.ext4 $partRecover
    if [ $? -ne 0 ];then
        echo "Failed: format virtual disk failed!"
        return 1
    fi

    mkdir -p ${LogPath}recoverMntdir
    mount -t ext4 $partRecover ${LogPath}recoverMntdir
    if [ $? -ne 0 ];then
        echo "Failed: mount $partRecover failed!"
        return 1
    fi

    copyRecoverFile
    if [ $? -ne 0 ];then
        echo "Failed: copy recover file failed!"
        return 1
    fi

    umount ${LogPath}recoverMntdir
    kpartx -d $loopdevice
    rm -rf ${LogPath}recoverMntdir
    rm -f ${LogPath}/os.img
}
# end

# ************************fillSectors****************************
# input:
# parameters1: output image
# ***************************************************************
function fillSectors()
{
    local file_size=`wc -c < $1`
    local seek_cnt=$[${file_size}/4]
    local word_cnt=$[128-${seek_cnt}]

    dd if=/dev/zero of=$1 count=${word_cnt} bs=4 seek=${seek_cnt}
}

# ************************writePartitionHeader**************************************
# Description:  write partirion header
# ******************************************************************************
function writePartitionHeader()
{
    #sector 512
    secStart=16
    MAIN_HEADER=$(printf "%#x" $COMPONENTS_MAIN_OFFSET)
    BACK_HEADER=$(printf "%#x" $COMPONENTS_BACKUP_OFFSET)

    MAIN_A=$(printf "%x" $(( ($MAIN_HEADER & 0xFF000000) >> 24 )))
    MAIN_B=$(printf "%x" $(( ($MAIN_HEADER & 0x00FF0000) >> 16 )))
    MAIN_C=$(printf "%x" $(( ($MAIN_HEADER & 0x0000FF00) >> 8)))
    MAIN_D=$(printf "%x" $(( $MAIN_HEADER & 0x000000FF )))

    BACKUP_A=$(printf "%x" $(( ($BACK_HEADER & 0xFF000000) >> 24 )))
    BACKUP_B=$(printf "%x" $(( ($BACK_HEADER & 0x00FF0000) >> 16 )))
    BACKUP_C=$(printf "%x" $(( ($BACK_HEADER & 0x0000FF00) >> 8)))
    BACKUP_D=$(printf "%x" $(( $BACK_HEADER & 0x000000FF )))

    if [ "$FS_BACKUP_FLAG"x = "on"x ]; then
        echo -e -n "\x55\xAA\x55\xAA\x44\xBB\x44\xBB" > magic
    else
        echo -e -n "\x55\xAA\x55\xAA" > magic
    fi
    echo -e -n "\x$MAIN_D\x$MAIN_C\x$MAIN_B\x$MAIN_A" > components_main_base
    echo 0000 0000 0000 0000 0000 0000\
        0004 0000 0000 0000 0008 0000 0000 0000\
        0004 0000 0000 0000 0010 0000 0000 0000\
        0010 0000 0000 0000 0020 0000 0000 0000\
        0000 0100 0000 0000 0000 0000 0000 0000\
        0000 0000 0000 0000 0000 0000 0000 0000 | xxd -r -ps >> components_main_base

    echo -e -n "\x$BACKUP_D\x$BACKUP_C\x$BACKUP_B\x$BACKUP_A" > components_backup_base
    echo 0000 0000 0000 0000 0000 0000\
        0004 0000 0000 0000 0008 0000 0000 0000\
        0004 0000 0000 0000 0010 0000 0000 0000\
        0010 0000 0000 0000 0020 0000 0000 0000\
        0000 0100 0000 0000 0000 0000 0000 0000\
        0000 0000 0000 0000 0000 0000 0000 0000 | xxd -r -ps >> components_backup_base

    fillSectors magic
    fillSectors components_main_base
    fillSectors components_backup_base

    dd if=magic of=${DEV_NAME} count=1 seek=$[secStart] bs=$sectorSize
    dd if=magic of=${DEV_NAME} count=1 seek=$[secStart+1] bs=$sectorSize
    dd if=components_main_base of=${DEV_NAME} count=1 seek=$[secStart+2] bs=$sectorSize
    dd if=components_backup_base of=${DEV_NAME} count=1 seek=$[secStart+3] bs=$sectorSize

    rm -rf magic
    rm -rf components_main_base
    rm -rf components_backup_base
}

function writeStructInfo()
{
    DEST_DEV=${DEV_NAME}
    if [ "$MAKE_IMGPK_FLAG"x = "on"x ];then
        DEST_DEV=$loopdevice
    fi
    if [ ! -f ${ScriptPath}parttion_head_info ];then
        echo "failed: parttion_head_info no exist"
        return 1
    fi
    if [ ! -f ${ScriptPath}boot_image_info ];then
        echo "failed: boot_image_info no exist"
        return 1
    fi

    #1M
    HEAD_OFFSET=2048
    #1M+64K
    HEAD_BAK_OFFSET=2176
    #1M+128K
    BOOTIMGDIR_OFFSET=2304
    #2M+128K
    BOOTCRL_OFFSET=4352

    dd if=${ScriptPath}parttion_head_info of=${DEST_DEV} seek=$[HEAD_OFFSET] count=2 bs=512
    dd if=${ScriptPath}parttion_head_info of=${DEST_DEV} seek=$[HEAD_BAK_OFFSET]  count=2 bs=512
    dd if=${ScriptPath}boot_image_info of=${DEST_DEV} seek=$[BOOTIMGDIR_OFFSET] count=8 bs=512
}
# ************************writeComponents**************************************
# Description:  write components main/backup
# ******************************************************************************
function writeComponents()
{
    FWM_DIR="${LogPath}squashfs-root/fw/"
    OF_DIR=$1

    if [[ -d "${FWM_DIR}" ]];then
        echo "fw dir exist"
    else
        echo "failed: fw dir no exist"
        return 1
    fi

    dd if=${FWM_DIR}lpm3.img of=${DEV_NAME} count=$LPM3_SIZE seek=$[OF_DIR+LPM3_OFFSET] bs=$sectorSize
    if [ $? -ne 0 ];then
        echo "failed: $OF_DIR lpm3"
        return 1
    fi
    dd if=${FWM_DIR}tee.bin of=${DEV_NAME} count=$TEE_SIZE seek=$[OF_DIR+TEE_OFFSET] bs=$sectorSize
    if [ $? -ne 0 ];then
        echo "failed: $OF_DIR tee"
        return 1
    fi
    dd if=${FWM_DIR}dt.img of=${DEV_NAME} count=$DTB_SIZE seek=$[OF_DIR+DTB_OFFSET] bs=$sectorSize
    if [ $? -ne 0 ];then
        echo "failed: $OF_DIR dt"
        return 1
    fi
    dd if=${FWM_DIR}Image of=${DEV_NAME} count=$IMAGE_SIZE seek=$[OF_DIR+IMAGE_OFFSET] bs=$sectorSize
    if [ $? -ne 0 ];then
        echo "failed: $OF_DIR Image"
        return 1
    fi
}

function write310BComponents()
{
    FWM_DIR="${LogPath}squashfs-root/fw/"
    OF_DIR=$1
    DEST_DEV=${DEV_NAME}
    if [ "$MAKE_IMGPK_FLAG"x = "on"x ];then
        DEST_DEV=$loopdevice
    fi
    if [[ -d "${FWM_DIR}" ]];then
        echo "fw dir exist"
    else
        echo "failed: fw dir no exist"
        return 1
    fi

    dd if=${FWM_DIR}Image of=${DEST_DEV} count=$IMAGE_SIZE seek=$[OF_DIR+IMAGE_OFFSET] bs=$sectorSize
    if [ $? -ne 0 ];then
        echo "failed: $OF_DIR Image"
        return 1
    fi
    dd if=${FWM_DIR}dt.img of=${DEST_DEV} count=$DTB_SIZE seek=$[OF_DIR+DTB_OFFSET] bs=$sectorSize
    if [ $? -ne 0 ];then
        echo "failed: $OF_DIR dt"
        return 1
    fi
    dd if=${FWM_DIR}itrustee.img of=${DEST_DEV} count=$TEE_SIZE seek=$[OF_DIR+TEE_OFFSET] bs=$sectorSize
    if [ $? -ne 0 ];then
        echo "failed: $OF_DIR itrustee"
        return 1
    fi

    if [ "$CARD_TYPE"x == "USB"x ];then
        dd if=${FWM_DIR}initrd_usb of=${DEST_DEV} count=$INITRD_SIZE seek=$[OF_DIR+INITRD_OFFSET] bs=$sectorSize
        if [ $? -ne 0 ];then
            echo "failed: $OF_DIR initrd_usb"
            return 1
        fi
    elif [[ $OF_DIR =~ "RECOVER" ]];then
        dd if=${FWM_DIR}initrd of=${DEST_DEV} count=$INITRD_SIZE seek=$[OF_DIR+INITRD_OFFSET] bs=$sectorSize
        if [ $? -ne 0 ];then
            echo "failed: $OF_DIR initrd"
            return 1
        fi
    fi

}

function configComponents()
{
    echo "Process: 4/4(Write main/backup)"
    writeComponents COMPONENTS_MAIN_OFFSET
    if [ $? -ne 0 ];then
        echo "Failed: writeComponents main"
        return 1
    fi
    echo "writeComponents main Succ"

    writeComponents COMPONENTS_BACKUP_OFFSET
    if [ $? -ne 0 ];then
        echo "Failed: writeComponents backup"
        return 1
    fi
    echo "writeComponents backup Succ"

    # write Partition Header
    writePartitionHeader
    if [ $? -ne 0 ];then
        echo "Failed: writePartitionHeader"
        return 1
    fi
    echo "writePartitionHeader Succ"
}

function config310BComponents()
{
    echo "Process: 4/4(Write Components)"

    writeStructInfo
    write310BComponents BOOTIMG_OFFSET_A
    if [ $? -ne 0 ];then
        echo "Failed: writeComponents BOOTIMG_A"
        return 1
    fi

    write310BComponents BOOTIMG_OFFSET_B
    if [ $? -ne 0 ];then
        echo "Failed: writeComponents BOOTIMG_B"
        return 1
    fi

    if [ $MAKE_IMGPK_FLAG = "on" ];then
        write310BComponents RECOVER_BOOTIMG_OFFSET_E
        if [ $? -ne 0 ];then
            echo "Failed: writeComponents RECOVER_BOOTIMG_OFFSET_E"
            return 1
        fi
        write310BComponents RECOVER_BOOTIMG_OFFSET_F
        if [ $? -ne 0 ];then
            echo "Failed: writeComponents RECOVER_BOOTIMG_OFFSET_F"
            return 1
        fi
        #unmap img file
        losetup -d $loopdevice
    fi
}

function umountDirCheck()
{
    local tmpn="$1"
    umount ${tmpn} 2>/dev/null
    if [[ $? -ne 0 ]];then
        echo "Failed: Umount ${tmpn} to SDcard failed!"
        return 1
    fi
}

function umountDir()
{
    if [ $FLAG_310B = "on" ] && [ $MAKE_IMGPK_FLAG = "on" ];then
        return 0
    fi
    if [ $FLAG_310B = "on" ];then
        umountDirCheck ${TMPDIR_SD_MOUNT}
        if [ "$FS_BACKUP_FLAG"x = "on"x ]; then
            umountDirCheck ${TMPDIR_SD2_MOUNT}
        fi
        umountDirCheck ${TMPDIR_SD3_MOUNT}
        umountDirCheck ${TMPDIR_SD4_MOUNT}
        return 0;
    fi
    umountDirCheck ${TMPDIR_SD_MOUNT}
    umountDirCheck ${TMPDIR_SD2_MOUNT}
    umountDirCheck ${TMPDIR_SD3_MOUNT}
    if [ "$FS_BACKUP_FLAG"x = "on"x ]; then
        umountDirCheck ${TMPDIR_SD4_MOUNT}
    fi
}
# ########################Begin Executing######################################
# ************************Check args*******************************************
function main()
{
    echo "make_sd_process: 2%"
    if [[ $# -lt 6 ]];then
        echo "Failed: Number of parameter illegal! Usage: $0 <dev fullname> <img path> <iso fullname> <net ip> <usb net ip> <result filename>"
        return 1;
    fi
    if [ X${MAKE_OS_RESULT} = "X" ];then
        echo "Failed: Result file name is NULL."
        return 1;
    fi

    # ********************** check chiptype **************************
    checkChipType

    # ********************** check configuration **************************
    checkConfig || return 1

    # ***************check network and usb card ip**********************************
    checkIps
    if [ $? -ne 0 ];then
        return 1
    fi
    # ***************check driver package and ubuntu iso**********************************
    checkPackage
    if [ $? -ne 0 ]; then
        return 1
    fi
    # ************************umount dev_name***************************************
    checkSDCard
    if [ $? -ne 0 ];then
        return 1
    fi

    # ************************Extract ubuntufs**************************************
    # output:squashfs-root/
    ubuntufsExtract
    if [ $? -ne 0 ];then
        return 1
    fi
    # end

    # ************************Check architecture************************************
    arch=$(uname -m)
    if [[ ${arch} =~ "x86" ]];then
         cp /usr/bin/qemu-aarch64-static ${LogPath}squashfs-root/usr/bin/
         if [ $? -ne 0 ];then
             echo "Failed: qemu-user-static or binfmt-support not found!"
             return 1;
         fi
         chmod 755 ${LogPath}squashfs-root/usr/bin/qemu-aarch64-static
    fi
    # end

    # ************************Configure ubuntu**************************************
    echo "Process: 1/4(Configure filesystem)"
    configFilesystem
    if [ $? -ne 0 ];then
        return 1
    fi
    # end

    # ************************Format SDcard*****************************************
    echo "Process: 2/4(Format SDcard)"
    configSDcard

    # ************************Copy files to SD**************************************
    echo "Process: 3/4(Pre install each run package and copy filesystem to SDcard)"
    if [ $FLAG_310B = "on" ];then
        preInstallMinirc310BPackage
        if [ $? -ne 0 ];then
            return 1
        fi
    else
        preInstallMinircPackage
        if [ $? -ne 0 ];then
            return 1
        fi
    fi
    # end

    # ************************write Components**************************************
    if [ $FLAG_310B = "on" ] && [ $MAKE_IMGPK_FLAG = "on" ];then
        makeInitrdImg
        if [ $? -ne 0 ];then
            return 1
        fi
    fi

    if [ "$FLAG_310B" = "on" ];then
        config310BComponents
    else
        configComponents
    fi

    umountDir
    echo "Finished!"
    return 0
}

main $*
ret=$?
#clean files
if [ "$CARD_TYPE"x == "M.2"x ];then
    echo "make M.2 SATA SSD/USB finished ,clean files"
elif [ "$CARD_TYPE"x == "NVME"x ];then
    echo "make M.2 NVME SSD/USB finished ,clean files"
elif [ "$CARD_TYPE"x == "USB"x ];then
    mkdir -p /mnt/usb
    mount ${DEV_NAME}$p2 /mnt/usb
    cp ${ScriptPath}recoverfs-*-eMMC.img /mnt/usb/opt/
    umount /mnt/usb
    echo "make USB finished ,clean files"
else
    echo "make sd card finished ,clean files"
fi
filesClean

if [[ ret -ne 0 ]];then
    echo "Failed" > ${LogPath}/${MAKE_OS_RESULT}
    exit 1
fi
echo "Success" > ${LogPath}/${MAKE_OS_RESULT}
exit 0
# end
