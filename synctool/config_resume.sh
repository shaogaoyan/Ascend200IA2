#!/bin/bash

backup_base_dir=/home/data/etc
resume_log_file=/home/log/resume.log
func_log()
{
    local added_info="[${FUNCNAME[1]}]"
    echo "[`date +%Y"-"%m"-"%d" "%T`] ${added_info} $@" |tee -a ${resume_log_file}
    chmod 640 ${resume_log_file}
    return 0
}

function dir_add_file_resume()
{
    dir_list=$(cat /usr/local/scripts/backup_dir_list.txt)
    for i in $dir_list
    do
        for j in $(ls -l ${backup_base_dir}/${i#/etc/} | grep -v .sha512 | awk '{print $9}')
        do
            add_file_name+="$i$j\n"
        done
    done

    add_file_list+=$(echo -e $add_file_name)
    for i in ${add_file_list}
    do
        if [ ! -e $i ] ;then
            tmp_check=$(sha512sum ${backup_base_dir}/${i#/etc/} | awk '{print $1}')
            file_check=$(cat ${backup_base_dir}/${i#/etc/}.sha512 | awk '{print $1}')
            if [ "$tmp_check" == "$file_check" ];then
                func_log "copy ${backup_base_dir}/${i#/etc/} to $(dirname $i)"
                if [ ! -d $(dirname $i) ];then
                    mkdir -p $(dirname $i)
                fi
                cp -af ${backup_base_dir}/${i#/etc/} $(dirname $i)
            else
                func_log "${backup_base_dir}/${i#/etc/} check failed, cancel copy."
            fi
        fi
    done

    if [ ! -f /etc/docker/daemon.json ] && [ -f ${backup_base_dir}/docker/daemon.json ];then
        tmp_check=$(sha512sum ${backup_base_dir}/docker/daemon.json | awk '{print $1}')
        file_check=$(cat ${backup_base_dir}/docker/daemon.json.sha512 | awk '{print $1}')
        if [ "$tmp_check" == "$file_check" ];then
            func_log "copy ${backup_base_dir}/docker/daemon.json} to /etc/docker/"
            cp -af ${backup_base_dir}/docker/daemon.json} /etc/docker/
        else
            func_log "/home/data/etc/docker/daemon.json check failed, cancel copy."
        fi
    fi
}

#common resume file for sys_file and backup_file
common_file_resume()
{
    create_backup_dir /usr/local/scripts/backup_file_list.txt
    create_backup_dir /usr/local/scripts/backup_dir_list.txt
    file_list=`cat /usr/local/scripts/backup_file_list.txt`
    dir_list=$(cat /usr/local/scripts/backup_dir_list.txt)

    for i in $dir_list
    do
        for j in $(ls -l $i | awk '{print $9}')
        do
            new_file_name+="$i$j\n"
        done
    done
    file_list+=" \n"
    file_list=$(echo -e $file_list)
    file_list+=$(echo -e $new_file_name)

    for i in ${file_list}
    do
        target_file=$i
        backup_file=${backup_base_dir}/${target_file#/etc/}
        check_file=backup_check

        if [ "$target_file" == "/etc/modules-load.d/10-atlas-default.conf" ];then
            continue
        fi

        if [ -d $target_file ];then
            continue
        fi

        if [ ! -f ${backup_file}.sha512 ] && [ ! -f ${backup_file} ] && [ -s ${target_file} ];then
            #met a new backup file
            func_log ${LINENO} :found a new backup file:${target_file}!
            #create dir for the new file
            mkdir -p `dirname ${backup_file}`
            #refresh verification for target file!
            sha512sum ${target_file} > /run/${check_file}.sha512
            dd if=/run/${check_file}.sha512 of=${backup_file}.sha512 conv=fsync status=none
            if [ "${target_file}" == "/etc/localtime" ] || [ "${target_file}" == "/etc/rc.local" ];then
                cp -af ${target_file} ${backup_base_dir}/
                ln -sf $(realpath "$target_file") ${backup_base_dir}/${target_file#/etc/} 
            else
                cp -af ${target_file} ${backup_file}
            fi
            #upgrade backup file!
        else
            verify_fail=0
            if [ ! -s ${backup_file}.sha512 ];then
                func_log ${LINENO} :verification lost:${target_file}!
                verify_fail=1
            else
                sha512sum -c ${backup_file}.sha512
                if [ $? -ne 0 ];then
                    func_log ${LINENO} :work file verify failed:${target_file}!
                    verify_fail=1
                else
                    verify_fail=0
                fi
            fi
            
            if [ $verify_fail -ne 0 ];then
                if [ ! -s ${backup_file} ];then
                    func_log ${LINENO} :fatal error! backup file zero length or not exist:${target_file}!
                else
                    func_log ${LINENO} :resume work file:${target_file}!
                    #resume work file
                    if [ "${target_file}" == "/etc/localtime" ] || [ "${target_file}" == "/etc/rc.local" ];then
                        cp -af ${backup_file} /etc/
                    else
                        if [ "${target_file}" == "/etc/docker/daemon.json" ];then
                            if [ ! -d /etc/docker ];then
                                mkdir -p /etc/docker
                            fi
                        fi
                        cp -a ${backup_file} ${target_file}
                    fi

                    #refresh verification
                    func_log ${LINENO} :refresh verification:${target_file}!
                    sha512sum ${target_file} > /run/${check_file}.sha512
                    dd if=/run/${check_file}.sha512 of=${backup_file}.sha512 conv=fsync status=none
                fi
            else
                diff ${target_file} ${backup_file}
                if [ $? -ne 0 ];then
                    func_log ${LINENO} :upgrade backup file:${target_file}!
                    if [ "${target_file}" == "/etc/localtime" ] || [ "${target_file}" == "/etc/rc.local" ];then
                        cp -af ${target_file} ${backup_base_dir}/
                        ln -sf $(realpath "$target_file") ${backup_base_dir}/${target_file#/etc/} 
                    else
                        cp -af ${target_file} ${backup_file}
                    fi
                else
                    func_log ${LINENO} :work verify backup ok:${target_file}!
                fi
            fi
        fi
    done
}

account_file_resume()
{
    file_list=`cat /usr/local/scripts/acount_backup_file.grp`
    verify_fail=0
    if [ ! -s ${backup_base_dir}/account_check.sha512 ] || [ ! -s ${backup_base_dir}/account_check.vrf ];then
        func_log ${LINENO} :verification file lost!
        verify_fail=1
    else
        sha512sum -c ${backup_base_dir}/account_check.vrf
        if [ $? -ne 0 ];then
            func_log ${LINENO} :verification file verify failed!
            verify_fail=1
        else
            sha512sum -c ${backup_base_dir}/account_check.sha512
            if [ $? -ne 0 ];then
                func_log ${LINENO} :work file verify failed!
                verify_fail=1
            else
                verify_fail=0
            fi
        fi
    fi
    # /etc/security/opasswd may be zero length
    if [ $verify_fail -ne 0 ];then
        backup_error=0
        for i in ${file_list}
        do
            target_file=$i
            if [ "${target_file}" != "/etc/security/opasswd" ];then
                if [ ! -s ${backup_base_dir}/${target_file#/etc/} ];then
                    func_log ${LINENO} :fatal error!backup file zero length or not exist:${target_file}!
                    backup_error=1
                fi
            else
                #/home/data/etc/security/opasswd must exist,but can be zero, other file must exist and no zero
                if [ ! -f ${backup_base_dir}/${target_file#/etc/} ];then
                    func_log ${LINENO} :fatal error!backup file not exist:${target_file}!
                    backup_error=1
                fi
            fi
        done
        
        if [ $backup_error -ne 0 ];then
            func_log ${LINENO} :resume work file failed!
        else
            func_log ${LINENO} :resume work file!
            for i in ${file_list}
            do
                target_file=$i
                cp -af ${backup_base_dir}/${target_file#/etc/} ${target_file}
            done
            #refresh verification
            func_log ${LINENO} :refresh verification file!
            rm -f /run/account_check.sha512
            for i in ${file_list}
            do
                target_file=$i
                sha512sum ${target_file} >> /run/account_check.sha512
            done
            dd if=/run/account_check.sha512 of=${backup_base_dir}/account_check.sha512 conv=fsync status=none
            sha512sum ${backup_base_dir}/account_check.sha512 > /run/account_check.vrf
            dd if=/run/account_check.vrf of=${backup_base_dir}/account_check.vrf conv=fsync status=none
        fi
    else
        for i in ${file_list}
        do
            target_file=$i
            diff ${target_file} ${backup_base_dir}/${target_file#/etc/}
            if [ $? -ne 0 ];then
                func_log ${LINENO} :upgrade backup file:${target_file}!
                cp -af ${target_file} ${backup_base_dir}/${target_file#/etc/}
            else
                func_log ${LINENO} :work verify bakcup ok:${target_file}!
            fi
        done
    fi
    func_log ${LINENO} :account_file check done!
}

create_backup_dir()
{
    local dirname=$(cat $1)
    for i in ${dirname}
    do
        if [ -f $i ];then
            target_file=$(dirname $i)
        elif [ -d $i ];then
            target_file=$i
        fi
        echo "mkdir ${backup_base_dir}${target_file#/etc}"
        mkdir -p ${backup_base_dir}${target_file#/etc}
    done
}

common_check_resume()
{
    create_backup_dir /usr/local/scripts/backup_file_list.txt
    create_backup_dir /usr/local/scripts/backup_dir_list.txt
    file_list=`cat /usr/local/scripts/backup_file_list.txt`
    dir_list=$(cat /usr/local/scripts/backup_dir_list.txt)

    for i in $dir_list
    do
        for j in $(ls -l $i | awk '{print $9}')
        do
            new_file_name+="$i$j\n"
        done
    done

    file_list+=" \n"
    file_list=$(echo -e $file_list)
    file_list+=$(echo -e $new_file_name)

    for i in ${file_list}
    do
        target_file=$i
        backup_file=${backup_base_dir}/${target_file#/etc/}
        check_file=backup_check
        verify_fail=0

        if [ "$target_file" == "/etc/modules-load.d/10-atlas-default.conf" ];then
            continue
        fi

        if [ -d $target_file ];then
            continue
        fi

        if [ -s ${backup_file} ];then
            diff ${backup_file} ${target_file}
            if [ $? -ne 0 ];then
                func_log ${LINENO} :upgrade work file:${target_file}!
                if [ "${target_file}" == "/etc/localtime" ] || [ "${target_file}" == "/etc/rc.local" ];then
                    cp -a ${backup_file} /etc/
                else
                    if [ "${target_file}" == "/etc/docker/daemon.json" ];then
                        if [ ! -d /etc/docker ];then
                            mkdir -p /etc/docker
                        fi
                    fi
                    cp -af ${backup_file} ${target_file}
                fi
            else
                func_log ${LINENO} :work==backup file:${target_file}!
            fi
        else
            if [ -s ${target_file} ];then
                func_log ${LINENO} :upgrade backup file:${target_file}!
                if [ "${target_file}" == "/etc/localtime" ] || [ "${target_file}" == "/etc/rc.local" ];then
                    cp -a ${target_file} ${backup_base_dir}/
                    ln -sf $(realpath "$target_file") ${backup_base_dir}/${target_file#/etc/} 
                else
                    cp -af ${target_file} ${backup_file}
                fi
            else
                func_log ${LINENO} :fatal error!both work and backup file lost:${target_file}!
                verify_fail=1
            fi
        fi

        #refresh verification for target file!
        if [ $verify_fail -eq 0 ];then
            func_log ${LINENO} :refresh verification:${target_file}!
            sha512sum ${target_file} > /run/${check_file}.sha512
            dd if=/run/${check_file}.sha512 of=${backup_file}.sha512 conv=fsync status=none
        else
            func_log ${LINENO} :check resume failed:${target_file}!
        fi
    done
}

account_check_resume()
{
    create_backup_dir /usr/local/scripts/acount_backup_file.grp
    file_list=`cat /usr/local/scripts/acount_backup_file.grp`
    backup_error=0
    for i in ${file_list}
    do
        target_file=$i
        if [ "${target_file}" != "/etc/security/opasswd" ];then
            if [ ! -s ${backup_base_dir}/${target_file#/etc/} ];then
                func_log ${LINENO} :account backup file zero length or not exist:${target_file}!
                backup_error=1
            fi
        else
            #/home/data/etc/security/opasswd must exist,but can be zero, other file must exist and no zero
            if [ ! -f ${backup_base_dir}/${target_file#/etc/} ];then
                func_log ${LINENO} :account backup file not exist:${target_file}!
                backup_error=1
            fi
        fi
    done

    work_error=0
    for i in ${file_list}
    do
        target_file=$i
        if [ "${target_file}" != "/etc/security/opasswd" ];then
            if [ ! -s ${target_file} ];then
                func_log ${LINENO} :account work file zero length or not exist:${target_file}!
                work_error=1
            fi
        else
            #/home/data/etc/security/opasswd must exist,but can be zero, other file must exist and no zero
            if [ ! -f ${target_file} ];then
                func_log ${LINENO} :account work file not exist:${target_file}!
                work_error=1
            fi
        fi
    done
    
    verify_fail=0
    if [ $backup_error -eq 0 ];then
        for i in ${file_list}
        do
            target_file=$i
            diff ${backup_base_dir}/${target_file#/etc/} ${target_file}
            if [ $? -ne 0 ];then
                func_log ${LINENO} :upgrade work file:${target_file}!
                cp -af ${backup_base_dir}/${target_file#/etc/} ${target_file}
            else
                func_log ${LINENO} :work==backup file:${target_file}!
            fi
        done
    else
        if [ $work_error -eq 0 ];then
            for i in ${file_list}
            do
                target_file=$i
                diff ${target_file} ${backup_base_dir}/${target_file#/etc/}
                if [ $? -ne 0 ];then
                    func_log ${LINENO} :upgrade backup file:${target_file}!
                    cp -af ${target_file} ${backup_base_dir}/${target_file#/etc/}
                else
                    func_log ${LINENO} :work==backup file:${target_file}!
                fi
            done
        else
            func_log ${LINENO} :fatal error!both work and backup file for account error!
            verify_fail=1
        fi
    fi
    
    #refresh verification for target file!
    if [ $verify_fail -eq 0 ];then
        func_log ${LINENO} :refresh account verification file!
        rm -f /run/account_check.sha512
        for i in ${file_list}
        do
            target_file=$i
            sha512sum ${target_file} >> /run/account_check.sha512
        done
        dd if=/run/account_check.sha512 of=${backup_base_dir}/account_check.sha512 conv=fsync status=none
        sha512sum ${backup_base_dir}/account_check.sha512 > /run/account_check.vrf
        dd if=/run/account_check.vrf of=${backup_base_dir}/account_check.vrf conv=fsync status=none
    else
        func_log ${LINENO} :check resume for account failed!
    fi
    func_log ${LINENO} :account_verify rebuild done!
}

if [ -f ${backup_base_dir}/etc_verify ];then
    account_file_resume
    common_file_resume
    diff ${backup_base_dir}/etc_verify /usr/local/scripts/etc_verify
    if [ $? -ne 0 ];then
        func_log ${LINENO} :etc_verify version changed!
        dd if=/usr/local/scripts/etc_verify of=${backup_base_dir}/etc_verify conv=fsync status=none
    fi
else
    account_check_resume
    common_check_resume
    dd if=/usr/local/scripts/etc_verify of=${backup_base_dir}/etc_verify conv=fsync status=none
    func_log ${LINENO} :etc_verify create!
fi
dir_add_file_resume

chmod 000 /etc/shadow
chmod 000 /home/data/etc/shadow

chmod 000 /etc/gshadow
chmod 000 /home/data/etc/gshadow

chmod 600 /etc/security/opasswd
chmod 600 /home/data/etc/security/opasswd

chmod 400 /etc/ssh/ssh_host_ecdsa_key
chmod 400 /etc/ssh/ssh_host_ecdsa_key.pub
chmod 400 /etc/ssh/ssh_host_ed25519_key
chmod 400 /etc/ssh/ssh_host_ed25519_key.pub
chmod 400 /etc/ssh/ssh_host_rsa_key
chmod 400 /etc/ssh/ssh_host_rsa_key.pub
chmod 600 /home/log/restore_factory.log
chmod 600 /usr/lib/rpm/rpm.log

chmod 600 /home/data/etc/ssh/sshd_config
chmod 400 /home/data/etc/ssh/ssh_host_ecdsa_key
chmod 400 /home/data/etc/ssh/ssh_host_ecdsa_key.pub
chmod 400 /home/data/etc/ssh/ssh_host_ed25519_key
chmod 400 /home/data/etc/ssh/ssh_host_ed25519_key.pub
chmod 400 /home/data/etc/ssh/ssh_host_rsa_key
chmod 400 /home/data/etc/ssh/ssh_host_rsa_key.pub

chmod 600 /etc/sysctl.conf
chmod 600 /home/data/etc/sysctl.conf
chmod 640 /home/data/etc/sysctl.d/20-euler.conf
chmod 640 /home/data/etc/sysctl.d/21-euler.conf
chmod 440 /etc/sudoers
chmod 440 /home/data/etc/sudoers
chmod 640 /home/data/etc/modprobe.d/blacklist.conf
chmod 640 /home/data/etc/ld.so.conf.d/mdc_hiva_ld.conf
chmod 600 /home/data/etc/modules-load.d/11-atlas.conf

chmod 755 /home/data/etc/sysconfig/network-scripts/ifdown
chmod 755 /home/data/etc/sysconfig/network-scripts/ifdown-bnep
chmod 755 /home/data/etc/sysconfig/network-scripts/ifdown-eth
chmod 755 /home/data/etc/sysconfig/network-scripts/ifdown-ippp
chmod 755 /home/data/etc/sysconfig/network-scripts/ifdown-ipv6
chmod 755 /home/data/etc/sysconfig/network-scripts/ifdown-post
chmod 755 /home/data/etc/sysconfig/network-scripts/ifdown-ppp
chmod 755 /home/data/etc/sysconfig/network-scripts/ifdown-routes
chmod 755 /home/data/etc/sysconfig/network-scripts/ifdown-sit
chmod 755 /home/data/etc/sysconfig/network-scripts/ifdown-tunnel
chmod 755 /home/data/etc/sysconfig/network-scripts/ifup
chmod 755 /home/data/etc/sysconfig/network-scripts/ifup-aliases
chmod 755 /home/data/etc/sysconfig/network-scripts/ifup-bnep
chmod 755 /home/data/etc/sysconfig/network-scripts/ifup-eth
chmod 755 /home/data/etc/sysconfig/network-scripts/ifup-ippp
chmod 755 /home/data/etc/sysconfig/network-scripts/ifup-ipv6
chmod 755 /home/data/etc/sysconfig/network-scripts/ifup-plip
chmod 755 /home/data/etc/sysconfig/network-scripts/ifup-plusb
chmod 755 /home/data/etc/sysconfig/network-scripts/ifup-post
chmod 755 /home/data/etc/sysconfig/network-scripts/ifup-ppp
chmod 755 /home/data/etc/sysconfig/network-scripts/ifup-routes
chmod 755 /home/data/etc/sysconfig/network-scripts/ifup-sit
chmod 755 /home/data/etc/sysconfig/network-scripts/ifup-tunnel
chmod 755 /home/data/etc/sysconfig/network-scripts/ifup-wireless
chmod 755 /home/data/etc/sysconfig/network-scripts/init.ipv6-global

sync -f

sleep 2
