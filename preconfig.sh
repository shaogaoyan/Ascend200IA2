#!/bin/bash

SCRIPTS_PATH="$( cd "$(dirname "$0")" ; pwd -P )""/"
SCRIPTS_NAME=$0
MAKECONF="mksd.conf"
PACKAGE_MATCH_NAME=$(ls Ascend*310*driver*.*)
FEATURE_FILE="feature.conf"

CONFIG_LIST=("FS_BACKUP_FLAG" "ROOT_PART_SIZE" "LOG_PART_SIZE")

# default config
FS_BACKUP_FLAG=off
FAST_BOOT_FLAG=off
ROOT_PART_SIZE=6144
LOG_PART_SIZE=1024
HOME_DATA_SIZE=1024


function exitHelp()
{
    echo "Usage:"
    printf "%-50s\n" "	$0 <cmd>"
    printf "%-50s%-50s\n" "	$0 check" "#run pre-check"
    printf "%-50s%-50s\n" "	$0 reconfigure" "#reconfigure"
    exit 1
}

function checkSupportFsBackup()
{
    local check_dir="${SCRIPTS_PATH}/checkdir"
    local feature_file
    local ret=1

    [ `find ${SCRIPTS_PATH} -name "${PACKAGE_MATCH_NAME}" | wc -l` -eq 1 ] || \
        { echo "[ERROR]Only support one driver packages in the installation directory." && exit 1; }
    package_name=`find ${SCRIPTS_PATH} -name "${PACKAGE_MATCH_NAME}"`
    which tar >/dev/null 2>&1 || { echo "[ERROR]command(tar) not found." && return 1; }

    [ -d "${check_dir}" ] || mkdir -p "${check_dir}"
    tar -zxf ${package_name} -C ${check_dir}
    feature_file=`find ${check_dir} -name ${FEATURE_FILE}`
    if [ -e "${feature_file}" ]; then
        source "${feature_file}"
        [ "${FEATURE_FS_BACKUP_SUPPORT}" == "y" ] && ret=0
    fi
    rm -rf ${check_dir}
    return ${ret}
}

function getUserInputYn()
{
    local yn_cnt=0
    while read yn
    do
	if [ "${yn}" == "y" ] || [ "${yn}" == "Y" ];then
            break
        elif [ "${yn}" == "n" ] || [ "${yn}" == "N" ];then
            return 1
        else
            let yn_cnt++
            if [ "${yn_cnt}" -gt 5 ];then
                return 1
            fi
            echo "[ERROR]Input error, please input [y/n] again!"
        fi
    done
}

function getUserInput()
{
    local user_input
    local default_flag=0
    read user_input
    if [ "${user_input}" == "" ] || [ "${user_input}" == "default" ]; then
        echo "[INFO]Use the default configuration."
        default_flag=1
        return 0
    fi

    case $1 in
        FS_BACKUP_FLAG)
            FS_BACKUP_FLAG=${user_input} 
            ;;
        ROOT_PART_SIZE)
            ROOT_PART_SIZE=${user_input}
            ;;
        LOG_PART_SIZE)
            LOG_PART_SIZE=${user_input}
            ;;
        HOME_DATA_SIZE)
            HOME_DATA_SIZE=${user_input}
            ;;
    esac
    return 0
}

# 1 means num, 0 means others
function checkNum()
{
    echo "$1" | [ -n "`sed -n '/^[0-9][0-9]*$/p'`" ] && return 1
    return 0
}

function checkPara()
{
    # fs must on/off
 
    if [[ "${FS_BACKUP_FLAG}" != "on" && "${FS_BACKUP_FLAG}" != "off" ]]; then
        echo "[WARNING]FS_BACKUP_FLAG does not match on/off."
        return 1
    fi
    if [ "${FS_BACKUP_FLAG}" == "on" ] && [ "${PACKAGE_MATCH_NAME}" != "$(ls Ascend*310b*driver* 2>/dev/null)" ]; then
        checkSupportFsBackup || \
            { echo "[ERROR]${package_name} does not support filesystem backup." && return 1; }
    fi
    echo "FS_BACKUP_FLAG ${FS_BACKUP_FLAG}"

    if [[ "${FAST_BOOT_FLAG}" != "on" && "${FAST_BOOT_FLAG}" != "off" ]]; then
        echo "[WARNING]FAST_BOOT_FLAG does not match on/off."
        return 1
    fi
    echo "FAST_BOOT_FLAG ${FAST_BOOT_FLAG}"

    # root must large than 2G
    checkNum ${ROOT_PART_SIZE}
    if [ $? -eq 0 ] || [ ${ROOT_PART_SIZE} -lt 2048 ]; then
        echo "[WARNING]ROOT_PART_SIZE is not a number or less than 2G."
        return 1
    fi
    echo "ROOT_PART_SIZE ${ROOT_PART_SIZE}(MB)"

    # log must large than 512M
    checkNum ${LOG_PART_SIZE}
    if [ $? -eq 0 ] || [ ${LOG_PART_SIZE} -lt 512 ]; then
        echo "[WARNING]LOG_PART_SIZE is not a number or less than 512M."
        return 1
    fi
    echo "LOG_PART_SIZE ${LOG_PART_SIZE}(MB)"
    checkNum ${HOME_DATA_SIZE}
    if [ $? -eq 0 ] || [ ${HOME_DATA_SIZE} -lt 512 ]; then
        echo "[WARNING]HOME_DATA_SIZE is not a number or less than 512M."
        return 1
    fi
    echo "HOME_DATA_SIZE ${HOME_DATA_SIZE}(MB)"
}

function checkConf()
{
    # the card capacity will check during partitioning

    # check range off every item
    checkPara || \
        { echo "[ERROR]Check parameter failed, please try again after reconfiguring." && return 1; }

    return 0
}

function setMakeconf()
{
    echo "FS_BACKUP_FLAG=${FS_BACKUP_FLAG}" >> ${MAKECONF}
    echo "FAST_BOOT_FLAG=off" >> ${MAKECONF}
    echo "ROOT_PART_SIZE=${ROOT_PART_SIZE}" >> ${MAKECONF}
    echo "LOG_PART_SIZE=${LOG_PART_SIZE}" >> ${MAKECONF}
    echo "HOME_DATA_SIZE=${HOME_DATA_SIZE}" >> ${MAKECONF}
    return 0
}

function createMakeconf()
{
    local user_input
    if [ -e ${MAKECONF} ]; then
        echo "[INFO]${MAKECONF} is exist, reconfiguration will overwrite ${MAKECONF}!"
        echo "[INFO]The old ${MAKECONF} will be rename to ${MAKECONF}.bak, do you want to continue (y/n)?"
        getUserInputYn || return 1
        mv ${MAKECONF} "${MAKECONF}.bak"
    fi

    touch ${MAKECONF}
    echo "#!""/bin/bash" >> ${MAKECONF}

    # use default configuration
    echo "[INFO]Do you want to use default configuration (y/n)?"
    read user_input
    if [ "${user_input}" == "y" ] || [ "${user_input}" == "" ]; then
        echo "[INFO]Use default configuration."
        setMakeconf || { echo "[ERROR]Set ${MAKECONF} failed" && return 1; }
        return 0
    fi

    echo "[INFO]Set filesystem backup enable type (on/off) (default off):"
    getUserInput FS_BACKUP_FLAG
    echo "[INFO]Set rootfs partitation size, enter a number(MB) (default 6144):"
    getUserInput ROOT_PART_SIZE
    echo "[INFO]Set log partitation size, enter a number(MB) (default 1024):"
    getUserInput LOG_PART_SIZE
    echo "[INFO]Set home data size, enter a number(MB) (default 1024):"
    getUserInput HOME_DATA_SIZE
    setMakeconf || { echo "[ERROR]Set ${MAKECONF} failed" && return 1; }

    return 0
}

function main()
{
    if [ ! -e ${MAKECONF} ]; then
        echo "[INFO]The ${MAKECONF} does not exist, do you want to create it (y/n)?"
        if getUserInputYn; then
            createMakeconf || { echo "[ERROR]Create makeconf failed." && return 1; }
        fi
    fi

    source ${MAKECONF} || \
        { echo "[ERROR]${MAKECONF} may has something wrong, please check and repair." && return 1; }

    checkConf || return 1
}

if [ $# -lt 1 ]; then
    exitHelp
fi

# start
case "$1" in
    check)
        main
        ;;
    reconfigure)
        createMakeconf
        checkConf
        ;;
    *)
        exitHelp
        ;;
esac
