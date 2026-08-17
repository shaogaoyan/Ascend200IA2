#!/bin/bash
#########################readme###############################
# This script is used to guide you to compile software packages
# to be added during file system creation.

# Attention: 
# ROOT_PATH must be $1(the fisrt para)
# BOOT_SH must be "${ROOT_PATH}/var/minirc_hook.sh"

# Scripts name:
# you hook scripts name must be minirc_install_hook.sh
##############################################################
#rootfs root path
ROOT_PATH=$1
#boot scripts, no need to modify
BOOT_SH="${ROOT_PATH}/var/minirc_hook.sh"
#this script directory
CUR_PATH="$(dirname $(readlink -f "$0"))"
#user package name, you must change name
AICPU_KERNELS_PACKAGE=$(ls Ascend310-aicpu_kernels-*.tar.gz)
ACLLIB_PACKAGE=$(ls Ascend-acllib-*.run)

######minirc_hook.sh header and ending, no need to modify######
function hook_head()
{
    echo "
#!/bin/bash
" >${BOOT_SH}
}

function hook_end()
{
    echo "
exit 0
" >>${BOOT_SH}
}
###############################################################

########################user function##########################
# generate acllib install shell in first system booting
# if you need add something into BOOT_SH, make sure you
# really want to do this in booting
function generateAclLibInstallShell()
{
    echo "
chown -fh HwHiAiUser:HwHiAiUser /home/HwHiAiUser/${ACLLIB_PACKAGE}
su - HwHiAiUser -s /bin/bash -c \"chmod -f 750 ${ROOT_PATH}/home/HwHiAiUser/$ACLLIB_PACKAGE\"
echo \"y
y
\" | su - HwHiAiUser -c \"/home/HwHiAiUser/${ACLLIB_PACKAGE} --run\"
rm -f /home/HwHiAiUser/${ACLLIB_PACKAGE}
" >>${BOOT_SH}
}

# copy acllib package into ${ROOT_PATH}/home/HwHiAiUser/ and add
# install step in first booting
function installAclLib()
{
    echo "start install acl lib"

    cp -f ${CUR_PATH}/$ACLLIB_PACKAGE ${ROOT_PATH}/home/HwHiAiUser/

    generateAclLibInstallShell

    echo "install acl lib end"
}

# using this as generateAclLibInstallShell()
function genAicpuKernInstShell()
{
    echo "
cd /root/aicpu_kernels_device/
chmod 750 *.sh
chmod 750 scripts/*.sh
scripts/install.sh --run

rm -rf /root/aicpu_kernels_device
" >>${BOOT_SH}
}

# using this as installAclLib()
function installAicpuKernels()
{
    tar zxf ${CUR_PATH}/${AICPU_KERNELS_PACKAGE} -C ${ROOT_PATH}/root/
    genAicpuKernInstShell
}

# your main func
function func_sample()
{
    echo "start install sample lib"
    #do copy
    installAclLib
    installAicpuKernels
}

# start
hook_head
# call your main func
func_sample
hook_end
chmod 750 ${BOOT_SH}
