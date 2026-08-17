#!/bin/bash

# ******************************for scp********************************************
loginname="HwHiAiUser"
userpswd=""
rootpswd=""

ip="192.168.0.2"

# ************************Variable*********************************************
ScriptPath="$( cd "$(dirname "$0")" ; pwd -P )""/"
ISO_FILE_DIR=$1
ISO_FILE=$2
# RUN_MINI=$3 # developerkit被拆分成3个包，这里传入参数没有developerkit_file_name

DRIVER_PACKAGE=$(ls Ascend310-driver-*.tar.gz)

NETWORK_CARD_DEFAULT_IP=$3
USB_CARD_DEFAULT_IP=$4

MAKE_OS_RESULT=$5

LogPath=${ScriptPath}"sd_card_making_log/"
TMPDIR_DATE=${LogPath}"no_touch_make_sd_dir"
RecoverLogPath=${LogPath}"make_os_sd.log"

USER_NAME="HwHiAiUser"
SYS_USER="HwSysUser"
DM_USER="HwDmUser"
BASE_USER="HwBaseUser"
USER_PWD="HwHiAiUser:\$6\$klSpdQ1K\$4Gm/7HxehX.YSum4Wf3IDFZ3v5L.clybUpGNGaw9zAh3rqzqB4mWbxvSTFcvhbjY/6.tlgHhWsbtbAVNR9TSI/:17795:0:99999:7:::"
ROOT_PWD="root:\$6\$klSpdQ1K\$4Gm/7HxehX.YSum4Wf3IDFZ3v5L.clybUpGNGaw9zAh3rqzqB4mWbxvSTFcvhbjY/6.tlgHhWsbtbAVNR9TSI/:17795:0:99999:7:::"

MAKECONF="mksd.conf"
MINIRC_LOGROTATE_DIR="/etc/crob.minirc/"
SYSLOG_MAXSIZE="1000M"
SYSLOG_ROTATE="4"
KERNLOG_MAXSIZE="1000M"
KERNLOG_ROTATE="4"

SD_FORMAT_TIMEOUT="900"
ALIVE_INTERVAL="10"

# ************************************verify password******************************
# Description: verify user and root password
# *********************************************************************************
function log_save()
{
    echo -e "$1" | tee -a ${RecoverLogPath}
}

function check_ret()
{
    local name=$1
    local value=$2
    case ${value} in
        0)
        log_save "[INFO]Verify ${name} passward: success."
        return 0
        ;;
        1)
        log_save "[ERROR]Spawn ssh failed and host key may had been changed."
        exit 1
        ;;
        2)
        log_save "[ERROR]${name} passwd is wrong or account temporarily is locked."
        exit 1
        ;;
        3)
        log_save "[WARNING]You are required to change ${name} password when log into recovery OS for the first time."
        exit 1
        ;;
        *)
        log_save "[ERROR]Something is wrong."
        exit 1
        ;;
    esac
}


function verify_user_passward()
{
	/usr/bin/expect<<-EOF
	set timeout 5
	spawn ssh -o GSSAPIAuthentication=no $ip -l $loginname -p 22
	expect {
	    "yes/no" {send "yes\r"; exp_continue}
	    "Account temporarily locked" {exit 2}
	    "*assword:" {send "${userpswd}\r"}
	    timeout {exit 4}
	}
	expect {
	    "Account temporarily locked" {exit 2}
	    "*hanging password" {exit 3}
	    "*assword:" {exit 2}
	    "HwHiAiUser" {exit 0}
	    "bash" {exit 0}
	    timeout {exit 4}
	}
	expect eof
	EOF
}

function verify_root_passward()
{
	/usr/bin/expect<<-EOF
	set timeout 5
	spawn ssh -o GSSAPIAuthentication=no $ip -l $loginname -p 22
	expect {
	    "yes/no" {send "yes\r"; exp_continue}
	    "*assword:" {send "${userpswd}\r"}
	    timeout {exit 4}
	}
	expect {
	    "Account temporarily locked" {exit 2}
	    "*hanging password" {exit 3}
	    "*assword:" {exit 2}
	    "HwHiAiUser" {send "su -\r"}
	    "bash" {send "su -\r"}
	    timeout {exit 4}
	}
	expect {
	    "Account temporarily locked" {exit 2}
	    "*assword:" {send "${rootpswd}\r"}
	    timeout {exit 4}
	}
	expect {
	    "*ermission denied" {exit 2}
	    "*hanging password" {exit 3}
	    "root" {exit 0}
	    "bash" {exit 0}
	    timeout {exit 4}
	}
	expect eof
	EOF
}

function verify_password()
{
    # verify default passwd
    verify_root_passward 1>>${RecoverLogPath} 2>&1
    case $? in
        0)
        echo "[INFO]Verify default passward: success."  >>${RecoverLogPath}
        return 0
        ;;
        1)
        log_save "[ERROR]Spawn ssh failed and host key may had been changed."
        exit 1
        ;;
        *)
        echo "[INFO]Verify default passward: fail." >>${RecoverLogPath}
        ;;
    esac

    # verify HwHiAiUser passwd
    local escape_str='"[]{}$'
    read -r -s -t 30 -p "please input ${loginname} password:" userpswd
    if [ $? -ne 0 ]; then
        log_save "\n[ERROR]Input passward overtime."
        exit 1
    fi

    userpswd=${userpswd//\\/\\\\}
    for i in `seq ${#escape_str}`
    do
        ch=${escape_str:$i-1:1}
        userpswd=${userpswd//${ch}/\\${ch}}
    done

    echo
    verify_user_passward 1>>${RecoverLogPath} 2>&1
    check_ret ${loginname} $?

    read -r -s -t 30 -p "please input root password:" rootpswd
    if [ $? -ne 0 ]; then
        log_save "\n[ERROR]Input passward overtime."
        exit 1
    fi

    # verify root passwd
    rootpswd=${rootpswd//\\/\\\\}
    for i in `seq ${#escape_str}`
    do
        ch=${escape_str:$i-1:1}
        rootpswd=${rootpswd//${ch}/\\${ch}}
    done

    echo
    verify_root_passward 1>>${RecoverLogPath} 2>&1
    check_ret "root" $?
}

verify_password
log_save "Start to make card in recovery mode. Please do not reboot or power off."

# ************************ssh_first_login*********************************************
# Description:  ssh_first_login
# ******************************************************************************
function ssh_first_login() 
{
	/usr/bin/expect<<-EOF
	set timeout 10
	spawn ssh -o GSSAPIAuthentication=no $ip -l $loginname -p 22
	expect {
		"(yes/no)" {send "yes\r";exp_continue}
		"*assword:" {send "$userpswd\r"}
	}
	expect "*\$"
	send "su -\r"
	expect "*assword:"
	send "$rootpswd\r"
	expect "*#"
	send "sed -i '/PermitRootLogin/c PermitRootLogin yes' /etc/ssh/sshd_config\r"
	expect "*#"
	send "kill -9 \\\$(ps -ef | grep /usr/sbin/sshd | grep -v grep | awk '{print \\\$1}')\r"
	expect "*\#"
	send "/usr/sbin/sshd -D &\r"
	expect "*\#"
	send "exit \r"
	send "exit \r"
	expect eof
	exit 1
	EOF
}

# ************************scp_login*********************************************
# Description: scp files to loopback
# ******************************************************************************
function scp_login()
{
	/usr/bin/expect<<-EOF
	set timeout -1
	spawn scp -o GSSAPIAuthentication=no -r $1 root@$ip:/$2
	expect {
		"(yes/no)" {send "yes\r";exp_continue}
		"*assword:" {send "$rootpswd\r"}
	}
	expect "*\#"
	exit 0
	expect eof
	exit 1
	EOF
}

# ************************ssh_login*********************************************
# Description: ssh order to loopback
# ******************************************************************************
function ssh_login()
{
	/usr/bin/expect<<-EOF
	set timeout $2
	spawn ssh -o GSSAPIAuthentication=no -o ServerAliveInterval=$ALIVE_INTERVAL root@$ip
	expect {
		"(yes/no)" {send "yes\r";exp_continue}
		"*assword:" {send "$rootpswd\r"}
	}
        expect "*\#"
        send "$1\r"
        expect "*\#"
        send "echo \$?\r"
        expect {
                "*1" {exit 1\r}
                "*0" {exit 0\r}
        }
	expect eof
	exit 1
	EOF
}

# ************************copy_tools*********************************************
# Description: copy tools to loopback
# ******************************************************************************
function copy_tools()
{
    scp_login "./tools/sd_tools" "/usr/sbin/"
    if [ $? -ne 0 ];then
        echo "Failed: scp sd_tools failed"
        return 1
    fi

    ssh_login "ln -sf /usr/sbin/sd_tools /usr/sbin/fdisk" "10"
    if [ $? -ne 0 ];then
        echo "Failed: link fdisk failed"
        return 1
    fi
    scp_login "./tools/mkfs.ext3" "/usr/sbin/"
    if [ $? -ne 0 ];then
        echo "Failed: scp ext3 failed"
        return 1
    fi
    ssh_login "ln -sf /usr/sbin/sd_tools /usr/sbin/dd" "10"
    if [ $? -ne 0 ];then
        echo "Failed: link dd failed"
        return 1
    fi

    ssh_login "chmod 755 /usr/sbin/sd_tools" "10"
    if [ $? -ne 0 ];then
        echo "Failed: chmod sd_tools failed"
        return 1
    fi
    ssh_login "chmod 755 /usr/sbin/fdisk" "10"
    if [ $? -ne 0 ];then
        echo "Failed: chmod fdisk failed"
        return 1
    fi
    ssh_login "chmod 755 /usr/sbin/mkfs.ext3" "10"
    if [ $? -ne 0 ];then
        echo "Failed: chmod ext3 failed"
        return 1
    fi
    ssh_login "chmod 755 /usr/sbin/dd" "10"
    if [ $? -ne 0 ];then
        echo "Failed: chmod dd failed"
        return 1
    fi
}

# ************************configure*********************************************
# Description:  configure
# ******************************************************************************
function checkConfig()
{
    source ${MAKECONF} || \
        { echo "[ERROR]${MAKECONF} may has something wrong, please check and repair." && return 1; }
    echo "record ${MAKECONF}" && cat ${MAKECONF}
    return 0
}

# ************************Cleanup*********************************************
# Description:  files cleanup
# ******************************************************************************
function filesClean()
{
    echo "make sd card finished, clean files"
    df -h | grep "${TMPDIR_DATE}"
    if [ $? -eq 0 ];then
        umount ${TMPDIR_DATE}
    fi
    rm -rf ${TMPDIR_DATE}
    df -h | grep "${LogPath}squashfs-root/cdtmp"
    if [ $? -eq 0 ];then
        umount ${LogPath}squashfs-root/cdtmp
    fi
    rm -rf ${LogPath}squashfs-root
    rm -rf ${LogPath}driver
    rm -rf ${LogPath}squashfs-root.tar.gz
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
    NETWORK_CARD_GATEWAY=`echo ${NETWORK_CARD_DEFAULT_IP} | sed -r 's/([0-9]+\.[0-9]+\.[0-9]+)\.[0-9]+/\1.1/g'`


    if [[ ${USB_CARD_DEFAULT_IP}"X" == "X" ]];then
        USB_CARD_DEFAULT_IP="192.168.1.2"
    fi

    checkIpAddr ${USB_CARD_DEFAULT_IP}
    if [ $? -ne 0 ];then
        echo "Failed: Invalid usb card ip."
        return 1
    fi
    return 0
}

# **************check driver package and ubuntu iso******************************
# Description:  check driver package and ubuntu iso: file exist, version match
# ******************************************************************************
function checkPackage()
{
    if [[ ${DRIVER_PACKAGE}"X" == "X" ]];then
        echo "[ERROR]Can not find driver package: Ascend310-driver-*.tar.gz."
        return 1
    fi
    if [[ ! -e ${ISO_FILE_DIR}/${ISO_FILE} ]];then
        echo "[ERROR]Can not find iso file."
        return 1
    fi

    if [[ $DRIVER_PACKAGE =~ "18.04" ]];then
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
      addresses: [${NETWORK_CARD_DEFAULT_IP}/24]
      gateway4: ${NETWORK_CARD_GATEWAY}
      nameservers:
            addresses: [255.255.0.0]

    usb0:
      dhcp4: no
      addresses: [${USB_CARD_DEFAULT_IP}/24]
      gateway4: ${NETWORK_CARD_GATEWAY}
"
    elif [[ $DRIVER_PACKAGE =~ "16.04" ]];then
        PACKAGE_VERSION="16.04"
        OS_TYPE="Ubuntu"
        ISO_SOURCE_VERSION="xenial main restrict"
        NETWORK_CFG_FILE="/etc/network/interfaces"
        NETWORK_CONFIG="source /etc/network/interfaces.d/*
auto lo
iface lo inet loopback

auto eth0
iface eth0 inet static
address ${NETWORK_CARD_DEFAULT_IP}
netmask 255.255.255.0
gateway ${NETWORK_CARD_GATEWAY}

auto usb0
iface usb0 inet static
address ${USB_CARD_DEFAULT_IP}
netmask 255.255.255.0
"
    elif [[ $DRIVER_PACKAGE =~ "openEuler" ]];then
        PACKAGE_VERSION=""
        OS_TYPE="openEuler"
        ISO_SOURCE_VERSION=""
        NETWORK_CFG_FILE="/etc/sysconfig/network-scripts/ifcfg-eth0"
        NETWORK_CONFIG="
TYPE=Ethernet
BOOTPROTO=static
DEFROUTE=yes
NAME=eth0
DEVICE=eth0
ONBOOT=yes
IPADDR=${NETWORK_CARD_DEFAULT_IP}
NETMASK=255.255.255.0
GATEWAY=${NETWORK_CARD_GATEWAY}
"
    elif [[ $DRIVER_PACKAGE =~ "euleros" ]];then
        PACKAGE_VERSION=""
	OS_TYPE="EulerOS"
        ISO_SOURCE_VERSION=""
        NETWORK_CFG_FILE="/etc/sysconfig/network-scripts/ifcfg-eth0"
        NETWORK_CONFIG="
TYPE=Ethernet
BOOTPROTO=static
DEFROUTE=yes
NAME=eth0
DEVICE=eth0
ONBOOT=yes
IPADDR=${NETWORK_CARD_DEFAULT_IP}
NETMASK=255.255.255.0
GATEWAY=${NETWORK_CARD_GATEWAY}
"
    else
        echo "unknown driver package version!!!"
        return 1
    fi
    if [[ $ISO_FILE =~ $PACKAGE_VERSION ]];then
        echo "[INFO]Start install ${OS_TYPE}-$PACKAGE_VERSION"
    else
        echo "[ERROR]Driver and ${OS_TYPE} iso do not match, please use ${OS_TYPE}$PACKAGE_VERSION"
        return 1
    fi

    return 0
}

# ************************Extract ubuntufs from iso*****************************
# Description:  mount iso file , extract root filesystem from squashfs, after
# execute function it will create squashfs-root/ in "./"
# ******************************************************************************
function ubuntufsExtract()
{
    mkdir ${TMPDIR_DATE}
    mount -o loop ${ISO_FILE_DIR}/${ISO_FILE} ${TMPDIR_DATE}

    if [[ $ISO_FILE =~ "ubuntu" ]];then 
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
            echo "Failed: cpio file' fail!"
            return 1;
        fi
        cd -
    elif [[ $ISO_FILE =~ "openEuler" ]];then
        cd ${LogPath}
        mkdir squashfs-root
        cd squashfs-root
        zcat ${ISO_FILE_DIR}/initrd.img.gz | cpio -divm
        if [[ $? -ne 0 ]];then
            echo "Failed: cpio file' fail!"
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

function configUbuntu()
{
    # 1. configure image sources
    mkdir -p ${LogPath}squashfs-root/cdtmp
    mount -o bind ${TMPDIR_DATE} ${LogPath}squashfs-root/cdtmp

    echo "
#!/bin/bash
${input_echo}

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
echo \"make_sd_process: 10%\"
apt-get install zlib -y
apt-get install python2.7 -y
apt-get install python3 -y
apt-get install pciutils -y
apt-get install nfs-common -y
apt-get install sysstat -y
apt-get install libelf1 -y
apt-get install libpython2.7 -y
apt-get install libnuma1 -y
echo \"make_sd_process: 20%\"
apt-get install dmidecode -y
apt-get install rsync -y
apt-get install net-tools -y
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

exit 0
\" > /etc/rc.local

chmod 755 /etc/rc.local
echo \"RuntimeMaxUse=50M\" >> /etc/systemd/journald.conf
echo \"SystemMaxUse=50M\" >> /etc/systemd/journald.conf

echo \"export LD_LIBRARY_PATH=/home/HwHiAiUser/Ascend/acllib/lib64\" >> /home/HwHiAiUser/.bashrc

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
    echo "
#!/bin/bash
${input_echo}

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
function formatSDcard()
{
    echo "
#!/bin/bash
DEV=\`fdisk -l | grep \"Disk /dev/mmcblk\" | awk -F ' ' 'NR==1 {print \$2}'\`
DEV_NAME=\`echo \${DEV%?}\`
ROOT_PART_SIZE=${ROOT_PART_SIZE}
LOG_PART_SIZE=${LOG_PART_SIZE}
FS_BACKUP_FLAG=${FS_BACKUP_FLAG}

#sectorEnd：最终区的末尾地址 sectorSize:扇区大小/byte sectorRsv:预留扇区大小
#536870912: 512M的byte数
sectorEnd=\`fdisk -l | grep \"\$DEV_NAME:\" | awk -F ' ' '{print \$7}'\`
sectorSize=\`fdisk -l | grep -A 3 \"\$DEV_NAME:\" | grep \"Units\" | awk -F ' ' '{print \$6}'\`
if [ \$sectorSize -ne 512 ];then
    echo \"Failed: sector size is not 512!\"
    return 1;
fi
sectorRsv=\$[536870912/sectorSize+1]
sectorEnd=\$[sectorEnd-sectorRsv]

# 1.umount all partition
function umountSDcard()
{
    df -h | grep \"/mnt/mnt_fs\"
    if [ \$? -eq 0 ];then
        umount /mnt/mnt_fs
    fi
    rm -rf /mnt/mnt_fs
    df -h | grep \"/mnt/mnt_logs\"
    if [ \$? -eq 0 ];then
        umount /mnt/mnt_logs
    fi
    rm -rf /mnt/mnt_logs
    df -h | grep \"/mnt/mnt_home_data\"
    if [ \$? -eq 0 ];then
        umount /mnt/mnt_home_data
    fi
    rm -rf /mnt/mnt_home_data

    if [ \${FS_BACKUP_FLAG} = \"on\" ]; then
        df -h | grep \"/mnt/mnt_fs_bak\"
        if [ \$? -eq 0 ];then
            umount /mnt/mnt_fs_bak
        fi
        rm -rf /mnt/mnt_fs_bak
    fi
}

# 2.format to ext3 filesystem and four partition(backup fs)
function formatSDcardFsBackup()
{
    echo begin_formatSDcardFsBackup
    umount \${DEV_NAME}* 2>/dev/null
    dd if=/dev/zero of=\${DEV_NAME} bs=1024 count=1024

    sectorOffset_1M=\$[1024*1024/sectorSize]
    sectorOffset1=\$sectorOffset_1M
    # End1: rootfs_part_size + 1M - 1
    sectorEnd1=\$[sectorOffset1+ROOT_PART_SIZE*sectorOffset_1M-1]
    # Offset2: rootfs_part_size + 1M
    sectorOffset2=\$[sectorEnd1+1]
    # End2: rootfs_part_size + 1M - 1
    sectorEnd2=\$[sectorOffset2+LOG_PART_SIZE*sectorOffset_1M-1]
    # Offset3: sectorEnd2 + 1
    sectorOffset3=\$[sectorEnd2+1]
    # End3: sectorEnd - p4 size
    sectorEnd3=\$[sectorEnd-ROOT_PART_SIZE*sectorOffset_1M]
    # Offset4: End3 + 1
    sectorOffset4=\$[sectorEnd3+1]

    #verifying the capacity
    curSector=\$[sectorEnd2+ROOT_PART_SIZE*sectorOffset_1M]
    if [ \$curSector -ge \$sectorEnd ]; then
        echo \"Failed: SD/eMMC capacity is less than user Configuration, please reconfigure and make later\"
        return 1
    fi

    echo \"n
p
1
\$sectorOffset1
\$sectorEnd1
n
p
2
\$sectorOffset2
\$sectorEnd2
n
p
3
\$sectorOffset3
\$sectorEnd3
n
p
\$sectorOffset4
\$sectorEnd
w
\" | fdisk \${DEV_NAME}

    partprobe

    fdisk -l

    sleep 5

    echo \"y
    \" | mkfs.ext3 -L ubuntu_fs \${DEV_NAME}p1
    if [[ \$? -ne 0 ]];then
        echo \"Failed: Format SDcard1 failed!\"
        return 1;
    fi

    echo \"y
    \" | mkfs.ext3 -L ubuntu_fs \${DEV_NAME}p2
    if [[ \$? -ne 0 ]];then
        echo \"Failed: Format SDcard2 failed!\"
        return 1;
    fi

    echo \"y
    \" | mkfs.ext3 -L ubuntu_fs \${DEV_NAME}p3
    if [[ \$? -ne 0 ]];then
        echo \"Failed: Format SDcard3 failed!\"
        return 1;
    fi

    echo \"y
    \" | mkfs.ext3 -L ubuntu_fs \${DEV_NAME}p4
    if [[ \$? -ne 0 ]];then
        echo \"Failed: Format SDcard4 failed!\"
        return 1;
    fi

    return 0
}

# 2.format to ext3 filesystem and three partition
function formatSDcard()
{
    echo begin_formatSDcard
    umount \${DEV_NAME}* 2>/dev/null
    dd if=/dev/zero of=\${DEV_NAME} bs=1024 count=1024

    sectorOffset_1M=\$[1024*1024/sectorSize]
    sectorOffset1=\$sectorOffset_1M
    # End1: rootfs_part_size + 1M - 1
    sectorEnd1=\$[sectorOffset1+ROOT_PART_SIZE*sectorOffset_1M-1]
    # Offset2: rootfs_part_size + 1M
    sectorOffset2=\$[sectorEnd1+1]
    # End2: rootfs_part_size + 1M - 1
    sectorEnd2=\$[sectorOffset2+LOG_PART_SIZE*sectorOffset_1M-1]
    # Offset3: sectorEnd2 + 1
    sectorOffset3=\$[sectorEnd2+1]

    #verifying the capacity
    curSector=\$sectorEnd2
    if [ \$curSector -ge \$sectorEnd ]; then
        echo \"Failed: SD/eMMC capacity is less than user Configuration, please reconfigure and make later\"
        return 1
    fi

    echo \"n
p
1
\$sectorOffset1
\$sectorEnd1
n
p
2
\$sectorOffset2
\$sectorEnd2
n
p
3
\$sectorOffset3
\$sectorEnd
w
\" | fdisk \${DEV_NAME}

    partprobe

    fdisk -l

    sleep 5

    echo \"y
    \" | mkfs.ext3 -L ubuntu_fs \${DEV_NAME}p1
    if [[ \$? -ne 0 ]];then
        echo \"Failed: Format SDcard1 failed!\"
        return 1;
    fi

    echo \"y
    \" | mkfs.ext3 -L ubuntu_fs \${DEV_NAME}p2
    if [[ \$? -ne 0 ]];then
        echo \"Failed: Format SDcard2 failed!\"
        return 1;
    fi

    echo \"y
    \" | mkfs.ext3 -L ubuntu_fs \${DEV_NAME}p3
    if [[ \$? -ne 0 ]];then
        echo \"Failed: Format SDcard3 failed!\"
        return 1;
    fi
    return 0
}

# 3.mkdir and mount 3 partition
mountSDcard()
{
    echo \"start mkdir\"
	mkdir /mnt/mnt_fs
	mount \${DEV_NAME}p1 /mnt/mnt_fs
	mkdir /mnt/mnt_logs
	mount \${DEV_NAME}p2 /mnt/mnt_logs
	mkdir /mnt/mnt_home_data
	mount \${DEV_NAME}p3 /mnt/mnt_home_data
    if [ \${FS_BACKUP_FLAG} = \"on\" ]; then
        mkdir /mnt/mnt_fs_bak
        mount \${DEV_NAME}p4 /mnt/mnt_fs_bak
    fi
}
umountSDcard || exit 1
if [ \${FS_BACKUP_FLAG} = \"on\" ]; then
    formatSDcardFsBackup || exit 1
else
    formatSDcard || exit 1
fi
mountSDcard || exit 1

# end" > ${LogPath}squashfs-root/format_card.sh

	echo "make_sd_process: 30%"
    ssh_first_login
    copy_tools
    if [ $? -ne 0 ];then
        return 1
    fi
	
	echo "make_sd_process: 35%"
    scp_login "${LogPath}squashfs-root/format_card.sh" "/bin"
    if [ $? -ne 0 ];then
        echo "[ERROR]scp format_card.sh failed"
        return 1
    fi
	
    echo "make_sd_process: 38%"
	rm -rf ${LogPath}squashfs-root/format_card.sh
    ssh_login "chmod 755 /bin/format_card.sh" "10"
    if [ $? -ne 0 ];then
        echo "[ERROR]chmod /bin/format_card.sh failed"
        return 1
    fi
	
	echo "make_sd_process: 40%"
    ssh_login "format_card.sh" $SD_FORMAT_TIMEOUT
    if [ $? -ne 0 ];then
        echo "[ERROR]format card failed"
        return 1
    fi
	echo "make_sd_process: 45%"
}
#end

# ************************Generate hook isntall*********************************
# Description: hook install
# ******************************************************************************
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

# ************************Copy files to SD**************************************
# Description:  copy rar and root filesystem to SDcard
# ******************************************************************************
function copyFilesToSDcard()
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
	echo "pre install driver end"
	
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

	echo "start copy files to emmc/sd card"
    tar zcf ${LogPath}squashfs-root.tar.gz -C ${LogPath}squashfs-root/ .

    scp_login "${LogPath}squashfs-root.tar.gz" "/home"
    if [ $? -ne 0 ];then
        echo "[ERROR]scp squashfs-root.tar.gz failed"
        return 1
    fi
    ssh_login "tar xfm /home/squashfs-root.tar.gz -C /mnt/mnt_fs" "360"
    if [ $? -ne 0 ];then
        echo "Failed: tar xfm squashfs-root.tar.gz failed"
        return 1
    fi
    ssh_login "\\\cp -rf /mnt/mnt_fs/home/* /mnt/mnt_home_data/" "100"
    if [ $? -ne 0 ];then
        echo "Failed: cp /home failed"
        return 1
    fi
    ssh_login "\\\cp -rf /mnt/mnt_fs/var/log/* /mnt/mnt_logs/" "100"
    if [ $? -ne 0 ];then
        echo "Failed: cp /var/log failed"
        return 1
    fi
    if [ "$FS_BACKUP_FLAG"x = "on"x ]; then
        ssh_login "tar xfm /home/squashfs-root.tar.gz -C /mnt/mnt_fs_bak" "360"
        if [ $? -ne 0 ];then
            echo "Failed: tar xfm squashfs-root.tar.gz failed"
            return 1
        fi
    fi
    return 0
}
# end

# ************************writeRawToSDcard**************************************
# Description:  write Header and main/backup component
# ******************************************************************************
function writeRawToSDcard()
{
echo "
#!/bin/bash

DEV=\`fdisk -l | grep \"Disk /dev/mmcblk\" | awk -F ' ' '{print \$2}'\`
DEV_NAME=\`echo \${DEV%?}\`

ROOT_PART_SIZE=${ROOT_PART_SIZE}
LOG_PART_SIZE=${LOG_PART_SIZE}
FS_BACKUP_FLAG=${FS_BACKUP_FLAG}

sectorEnd=\`fdisk -l | grep \"\$DEV_NAME:\" | awk -F ' ' '{print \$7}'\`
sectorSize=\`fdisk -l | grep -A 3 \"\$DEV_NAME:\" | grep \"Units\" | awk -F ' ' '{print \$6}'\`
if [ \$sectorSize -ne 512 ];then
    echo \"Failed: sector size is not 512!\"
    return 1;
fi
# 536870912 bytes is 512M
sectorRsv=\$[536870912/sectorSize+1]
sectorEnd=\$[sectorEnd-sectorRsv]

#component main/backup offset
COMPONENTS_MAIN_OFFSET=\$[sectorEnd+1]
COMPONENTS_BACKUP_OFFSET=\$[COMPONENTS_MAIN_OFFSET+73728]
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

function fillSectors()
{
    local file_size=\`wc -c < \$1\`
    local seek_cnt=\$[\${file_size}/4]
    local word_cnt=\$[128-\${seek_cnt}]
    dd if=/dev/zero of=\$1 count=\${word_cnt} bs=4 seek=\${seek_cnt}
}

function writePartitionHeader()
{
    #sector 512用变量
    secStart=16
    MAIN_HEADER=\$(printf \"%#x\" \$COMPONENTS_MAIN_OFFSET)
    BACK_HEADER=\$(printf \"%#x\" \$COMPONENTS_BACKUP_OFFSET)

    MAIN_A=\$(printf \"%x\" \$(( (\$MAIN_HEADER & 0xFF000000) >> 24 )))
    MAIN_B=\$(printf \"%x\" \$(( (\$MAIN_HEADER & 0x00FF0000) >> 16 )))
    MAIN_C=\$(printf \"%x\" \$(( (\$MAIN_HEADER & 0x0000FF00) >> 8)))
    MAIN_D=\$(printf \"%x\" \$(( \$MAIN_HEADER & 0x000000FF )))

    BACKUP_A=\$(printf \"%x\" \$(( (\$BACK_HEADER & 0xFF000000) >> 24 )))
    BACKUP_B=\$(printf \"%x\" \$(( (\$BACK_HEADER & 0x00FF0000) >> 16 )))
    BACKUP_C=\$(printf \"%x\" \$(( (\$BACK_HEADER & 0x0000FF00) >> 8)))
    BACKUP_D=\$(printf \"%x\" \$(( \$BACK_HEADER & 0x000000FF )))

    if [ \${FS_BACKUP_FLAG} = \"on\" ]; then
        echo -e -n \"\x55\xAA\x55\xAA\x44\xBB\x44\xBB\" > magic
    else
        echo -e -n \"\x55\xAA\x55\xAA\" > magic
    fi

    echo -e -n \"\x\$MAIN_D\x\$MAIN_C\x\$MAIN_B\x\$MAIN_A\" > components_main_base
    echo -e -n \"\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\" >> components_main_base
    echo -e -n \"\x00\x04\x00\x00\x00\x00\x00\x00\x00\x08\x00\x00\x00\x00\x00\x00\" >> components_main_base
    echo -e -n \"\x00\x04\x00\x00\x00\x00\x00\x00\x00\x10\x00\x00\x00\x00\x00\x00\" >> components_main_base
    echo -e -n \"\x00\x10\x00\x00\x00\x00\x00\x00\x00\x20\x00\x00\x00\x00\x00\x00\" >> components_main_base
    echo -e -n \"\x00\x00\x01\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\" >> components_main_base
    echo -e -n \"\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\" >> components_main_base

    echo -e -n \"\x\$BACKUP_D\x\$BACKUP_C\x\$BACKUP_B\x\$BACKUP_A\" > components_backup_base
    echo -e -n \"\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\" >> components_backup_base
    echo -e -n \"\x00\x04\x00\x00\x00\x00\x00\x00\x00\x08\x00\x00\x00\x00\x00\x00\" >> components_backup_base
    echo -e -n \"\x00\x04\x00\x00\x00\x00\x00\x00\x00\x10\x00\x00\x00\x00\x00\x00\" >> components_backup_base
    echo -e -n \"\x00\x10\x00\x00\x00\x00\x00\x00\x00\x20\x00\x00\x00\x00\x00\x00\" >> components_backup_base
    echo -e -n \"\x00\x00\x01\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\" >> components_backup_base
    echo -e -n \"\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\" >> components_backup_base

    fillSectors magic
    fillSectors components_main_base
    fillSectors components_backup_base

    dd if=magic of=\${DEV_NAME} count=1 seek=\$[secStart] bs=\$sectorSize
    dd if=magic of=\${DEV_NAME} count=1 seek=\$[secStart+1] bs=\$sectorSize
    dd if=components_main_base of=\${DEV_NAME} count=1 seek=\$[secStart+2] bs=\$sectorSize
    dd if=components_backup_base of=\${DEV_NAME} count=1 seek=\$[secStart+3] bs=\$sectorSize
}

function writeComponents()
{
    FWM_DIR=\"/mnt/mnt_fs/fw/\"
    OF_DIR=\$1

    if [[ -d \"\${FWM_DIR}\" ]];then
        echo \"fw dir exist\"
    else
        echo \"failed: fw dir no exist\"
        return 1
    fi

    dd if=\${FWM_DIR}lpm3.img of=\${DEV_NAME} count=\$LPM3_SIZE seek=\$[OF_DIR+LPM3_OFFSET] bs=\$sectorSize
    if [ \$? -ne 0 ];then
        echo \"failed: \$OF_DIR lpm3\"
        return 1
    fi
    dd if=\${FWM_DIR}tee.bin of=\${DEV_NAME} count=\$TEE_SIZE seek=\$[OF_DIR+TEE_OFFSET] bs=\$sectorSize
    if [ \$? -ne 0 ];then
        echo \"failed: \$OF_DIR tee\"
        return 1
    fi
    dd if=\${FWM_DIR}dt.img of=\${DEV_NAME} count=\$DTB_SIZE seek=\$[OF_DIR+DTB_OFFSET] bs=\$sectorSize
    if [ \$? -ne 0 ];then
        echo \"failed: \$OF_DIR dt\"
        return 1
    fi    
    dd if=\${FWM_DIR}Image of=\${DEV_NAME} count=\$IMAGE_SIZE seek=\$[OF_DIR+IMAGE_OFFSET] bs=\$sectorSize
    if [ \$? -ne 0 ];then
        echo \"failed: \$OF_DIR Image\"
        return 1
    fi
}

# ************************write Components************************************** 
writeComponents COMPONENTS_MAIN_OFFSET
if [ \$? -ne 0 ];then
    echo \"Failed: writeComponents main\"
    exit 1
fi
echo \"writeComponents main Succ\"
# end

writeComponents COMPONENTS_BACKUP_OFFSET
if [ \$? -ne 0 ];then
    echo \"Failed: writeComponents backup\"
    exit 1
fi
echo \"writeComponents backup Succ\"
# end

# ************************write Partition Header********************************
writePartitionHeader
if [ \$? -ne 0 ];then
    echo \"Failed: writePartitionHeader\"
    exit 1
fi
echo \"writePartitionHeader Succ\"
#end

umount /mnt/mnt_fs 2>/dev/null
if [[ \$? -ne 0 ]];then
    echo \"Failed: Umount /mnt/mnt_fs to SDcard failed!\"
    exit 1
fi
echo \"umount mnt_fs Succ\"

umount /mnt/mnt_logs 2>/dev/null
if [[ \$? -ne 0 ]];then
    echo \"Failed: Umount /mnt/mnt_logs to SDcard failed!\"
    exit 1
fi
echo \"umount mnt_logs Succ\"

umount /mnt/mnt_home_data 2>/dev/null
if [[ \$? -ne 0 ]];then
    echo \"Failed: Umount /mnt/mnt_home_data to SDcard failed!\"
    exit 1
fi
echo \"umount mnt_home_data Succ\"

if [ \${FS_BACKUP_FLAG} = \"on\" ]; then
    umount /mnt/mnt_fs_bak 2>/dev/null
    if [[ \$? -ne 0 ]];then
        echo \"Failed: Umount /mnt/mnt_fs_bak to SDcard failed!\"
        exit 1
    fi
    echo \"umount mnt_fs_bak Succ\"
fi

echo \"Finished!\"
exit 0
# end" > ${LogPath}squashfs-root/write_part.sh
    scp_login "${LogPath}squashfs-root/write_part.sh" "/bin"
    if [ $? -ne 0 ];then
        echo "[ERROR]scp write_part.sh failed"
        return 1
    fi
    ssh_login "chmod 755 /bin/write_part.sh" "10"
    if [ $? -ne 0 ];then
        echo "[ERROR]chmod write_part.sh failed"
        return 1
    fi 
    ssh_login "write_part.sh" $SD_FORMAT_TIMEOUT
    if [ $? -ne 0 ];then
        echo "[ERROR]write part failed"
        return 1
    fi
    rm -f ${LogPath}squashfs-root/write_part.sh
}

# ########################Begin Executing######################################
# ************************Check args*******************************************
function main()
{
	echo "make_sd_process: 2%"
    if [[ $# -lt 5 ]];then
        echo "Failed: Number of parameter illegal! Usage: $0 <img path> <iso fullname> <net ip> <usb net ip> <result filename>"
        return 1;
    fi

    if [ X${MAKE_OS_RESULT} = "X" ];then
        echo "Failed: Result file name is NULL."
        return 1;
    fi

    # ***************check tools is exist**********************************
    if [[ -d "./tools" ]];then
        echo "tools exist"
    else
        echo "failed: tools no exist, please check rar packets and add tools"
        return 1
    fi

    # ***************check ping loopback is ok**********************************
    if [ -e "/root/.ssh/known_hosts" ]; then
        ssh-keygen -f '/root/.ssh/known_hosts' -R $ip
        if [ $? -ne 0 ];then
            echo "Failed: remove ip ssh-keygen failed!"
            return 1
        fi
    fi
    ping -c 3 -w 3 $ip
    if [ $? -ne 0 ];then
        echo "Failed: ping $ip failed!"
        return 1
    fi

    # ********************** check configuration **************************
    checkConfig || return 1

    # ***************check network and usb card ip**********************************
    checkIps
    if [ $? -ne 0 ];then
        return 1
    fi
    # ***************check driver package and ubuntu iso**********************************
    checkPackage
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
    formatSDcard
    if [ $? -ne 0 ];then
        return 1
    fi
    # end

	echo "Process: 3/4(Copy filesystem and mini package to SDcard)"
    copyFilesToSDcard
    if [ $? -ne 0 ];then
        return 1
    fi
	
    echo "Process: 4/4(Write Raw firmware to SDcard)"
    writeRawToSDcard
    if [ $? -ne 0 ];then
        return 1
    fi
	
    return 0
}

main $* 1>>${RecoverLogPath} 2>&1
ret=$?
#clean files
filesClean 1>>${RecoverLogPath} 2>&1

if [[ ret -ne 0 ]];then
    echo "Failed" > ${LogPath}/${MAKE_OS_RESULT}
    exit 1
fi
echo "Success" > ${LogPath}/${MAKE_OS_RESULT}
exit 0
# end

