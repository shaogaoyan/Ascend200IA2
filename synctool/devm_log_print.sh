#!/bin/bash

# 默认参数
LOG_DIR="/var/plog"
LOG_FILE="/var/plog/devm_scripts_run.log"
DATA_FORMAT="+%Y-%m-%dT%T"

init_log_path()
{
    local log_name
    # 参获取日志保存路径
    if [[ "$#" == 2 ]]; then
        LOG_DIR="$1"
        log_name="$2"
        LOG_FILE="${LOG_DIR}/${log_name}"
    fi

    # 检测并创建日志
    if [[ -L ${LOG_DIR} ]]; then
        unlink ${LOG_DIR}
        mkdir -p ${LOG_DIR} && chmod 750 ${LOG_DIR}
    else
        if [[ ! -d ${LOG_DIR} ]]; then
            mkdir -p ${LOG_DIR} && chmod 750 ${LOG_DIR}
        fi
    fi

    if [[ -L ${LOG_FILE} ]]; then
        unlink ${LOG_FILE}
        touch ${LOG_FILE} && chmod 640 ${LOG_FILE}
    else
        if [[ ! -f ${LOG_FILE} ]]; then
            touch ${LOG_FILE} && chmod 640 ${LOG_FILE}
        fi
    fi
}

if [[ -t 1 ]] && [[ $((1$(tput colors 2> /dev/null))) -ge 18 ]]; then
    readonly color_red="$(tput setaf 1)"
    readonly color_yellow="$(tput setaf 3)"
    readonly color_green="$(tput setaf 2)"
    readonly color_norm="$(tput sgr0)"
else
    readonly color_red=""
    readonly color_yellow=""
    readonly color_green=""
    readonly color_norm=""
fi

if command -v caller >/dev/null 2>&1; then
    # return func(lineno:filename)
    # NOTE: skip 2-level inner frame
    _caller() { caller 2| awk '{sub(/.*\//,e,$3);print $2"("$3":"$1")"}'; }
else
    _caller() { :; }
fi

check_log_file()
{
    local real_name=$(readlink -f ${LOG_FILE})
    if [[ "${LOG_FILE}" != "${real_name}" ]]; then
        echo "log file is softlink!"
        return 1
    fi

    local log_size=$(ls -l ${LOG_FILE} | awk '{print $5}' | tr -d '\\n')
    # 日志大小超过1M，进行备份
    if [[ $log_size -ge 1048576 ]]; then
        mv "$LOG_FILE" "$LOG_FILE".bak
        touch ${LOG_FILE} && chmod 640 ${LOG_FILE}
    fi

    return 0
}

_log()
{
    LEVEL=$1
    shift 1

    check_log_file
    local ret=$?
    if [[ -f "${LOG_FILE}" && $ret -eq 0 ]]; then
        echo "$(date ${DATA_FORMAT}) [${LEVEL}][$(_caller)]: $*" >> ${LOG_FILE}
    fi
}

logger_debug()
{
    echo "$(date ${DATA_FORMAT})-${LEVEL}- $*"
}

logger_info()
{
    _log INFO "$@"
}

logger_warn()
{
    _log WARN "${color_yellow}$*${color_norm}"
}

logger_error()
{
    _log ERROR "${color_red}$*${color_norm}"
}
