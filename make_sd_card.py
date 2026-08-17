'''common installation'''
import os
import sys
import platform
import signal
import subprocess
import time
import re
import yaml

NETWORK_CARD_DEFAULT_IP = "192.168.0.2"
NETWORK_CIDR_PREFIX = "24"
NETWORK_DEFAULT_NETMASK = "255.255.255.0"
NETWORK_DEFAULT_GATEWAY = "192.168.0.1"
USB_CARD_DEFAULT_IP = "192.168.1.2"
MAKE_OS_RESULT = "make_os_sd.result"

CURRENT_PATH = os.path.dirname(
    os.path.realpath(__file__))

SD_CARD_MAKING_PATH = os.path.join(CURRENT_PATH, "sd_card_making")
PRECONFIG_PATH = os.path.join(CURRENT_PATH, "preconfig.sh")
PRECONFIG_COMMAND = "bash " + PRECONFIG_PATH + " check"

MIN_DISK_SIZE = 7 * 1024 * 1024 * 1024

MAKING_SD_CARD_COMMAND = "bash {path}/make_os_sd.sh " + " {dev_name}" + \
    " {pkg_path} {ubuntu_file_name}" + \
    " " + NETWORK_CARD_DEFAULT_IP + " " + NETWORK_CIDR_PREFIX + " " + NETWORK_DEFAULT_NETMASK + " " + \
    NETWORK_DEFAULT_GATEWAY + " " + USB_CARD_DEFAULT_IP + " " + MAKE_OS_RESULT + \
    " > {log_path}/make_os_sd.log 2>&1 "

MAKING_SATA_COMMAND = "bash {path}/make_os_sd.sh " + " {dev_name}" + \
    " {pkg_path} {ubuntu_file_name}" + \
    " " + NETWORK_CARD_DEFAULT_IP + " " + NETWORK_CIDR_PREFIX + " " + NETWORK_DEFAULT_NETMASK + " " + \
    NETWORK_DEFAULT_GATEWAY + " " + USB_CARD_DEFAULT_IP + " " + MAKE_OS_RESULT + \
    " {card_type}" + " > {log_path}/make_os_sd.log 2>&1 "

MAKING_RECOVER_COMMAND = "bash {path}/make_os_recover.sh " + \
    " {pkg_path} {ubuntu_file_name}" + \
    " " + NETWORK_CARD_DEFAULT_IP + " " + USB_CARD_DEFAULT_IP + " " + MAKE_OS_RESULT

COMMAND_MKRECOVERIMG = "mkrecoverimg"
COMMAND_LOCAL = "local"
COMMAND_RECOVER = "recover"

CARD_TYPE_LIST = ["M.2", "eMMC", "USB", "SD", "NVME"]
SSD_CARD_TYPE = ["M.2", "NVME"]

def execute(cmd, timeout=3600, cwd=None):
    '''execute os command'''
    is_linux = platform.system() == 'Linux'

    if not cwd:
        cwd = os.getcwd()
    process = subprocess.Popen(cmd, cwd=cwd, bufsize=32768, stdout=subprocess.PIPE,
                               stderr=subprocess.STDOUT, shell=True,
                               preexec_fn=os.setsid if is_linux else None)

    t_beginning = time.time()

    # cycle times
    time_gap = 0.01

    str_std_output = ""
    while True:

        str_out = str(process.stdout.read().decode())

        str_std_output = str_std_output + str_out

        if process.poll() is not None:
            break
        seconds_passed = time.time() - t_beginning

        if timeout and seconds_passed > timeout:

            if is_linux:
                os.kill(process.pid, signal.SIGTERM)
            else:
                process.terminate()
            return False, process.stdout.readlines()
        time.sleep(time_gap)
    str_std_output = str_std_output.strip()
    std_output_lines_last = []
    std_output_lines = str_std_output.split("\n")
    for i in std_output_lines:
        std_output_lines_last.append(i)

    if process.returncode != 0 or "Traceback" in str_std_output:
        return False, std_output_lines_last

    return True, std_output_lines_last


def print_process(string, is_finished=False):
    if string == "" or string is None or is_finished:
        print(".......... .......... .......... .......... 100%", end='\r')
        print("")
    else:
        string = string.split(".......... ", 1)[1]
        string = string.split("%")[0] + "%"
        print(string, end='\r')


def check_sd(dev_name):
    cmd_str = ""
    if dev_name_check(dev_name):
        cmd_str = "fdisk -l 2>/dev/null | grep \"Disk {dev_name}:\"".format(dev_name=dev_name)
    ret, disk = execute(cmd_str)

    if not ret or len(disk) > 1:
        print(
            "[ERROR] Can not get disk, please use fdisk -l to check available disk name!")
        return False

    ret, mounted_list = execute("df -h")

    if not ret:
        print("[ERROR] Can not get mounted disk list!")
        return False

    unchanged_disk_list = []
    for each_mounted_disk in mounted_list:
        disk_name = each_mounted_disk.split()[0]
        disk_type = each_mounted_disk.split()[5]
        if disk_type == "/boot" or disk_type == "/":
            unchanged_disk_list.append(disk_name)
    unchanged_disk = " ".join(unchanged_disk_list)

    disk_size_str = disk[0].split(", ")[1]
    disk_size_str = disk_size_str.split()[0]
    disk_size = int(disk_size_str)

    if dev_name not in unchanged_disk and disk_size >= MIN_DISK_SIZE:
        return True

    print("[ERROR] Invalid SD card or size is less then 8G, please check SD Card.")
    return False


def check_minirc_run_package():
    #check driver package
    ret, paths = execute(
        "find {path} -name \"Ascend*310*driver*.*\"".format(path=CURRENT_PATH))
    if not ret or not paths[0]:
        print("[ERROR]Can not find driver run package in current path")
        return False

    if len(paths) > 1:
        print("[ERROR]Too many driver packages, please delete redundant packages.")
        return False

    return True


def process_recover_installation():
    ret = check_minirc_run_package()
    if not ret:
        return False

    ret, paths = execute("whoami".format(path=CURRENT_PATH))
    if paths[0] != "root":
        print("[ERROR] the recover model only support in root user")
        return False

    confirm_tips = "Please make sure you have installed dependency packages:" + \
        "\n\t apt-get install -y qemu-user-static binfmt-support gcc-aarch64-linux-gnu \
        g++-aarch64-linux-gnu expect cpio gzip\n" + \
        "Please input Y: continue, other to install them:"
    confirm = input(confirm_tips)
    confirm = confirm.strip()

    if confirm != "Y" and confirm != "y":
        return False

    ret, _ = execute("rm -rf {path}_log/*".format(path=SD_CARD_MAKING_PATH))
    if not ret:
        print("[ERROR] Failed to remove the log directory")

    ret, _ = execute("mkdir -p {path}_log".format(path=SD_CARD_MAKING_PATH))
    if not ret:
        print("[ERROR] Failed to create the log directory")

    log_path = "{path}_log".format(path=SD_CARD_MAKING_PATH)
    ret, paths = execute(
        "find {path} -name \"Ascend310-driver-*.tar\"".format(path=CURRENT_PATH))
    if not ret:
        print("[ERROR] Can not find driver run package in current path")
        return False

    if len(paths) > 1:
        print(
            "[ERROR] Too many mini driver run packages, please delete redundant packages.")
        return False
    ascend_driver_path = paths[0]
    ascend_driver_file_name = os.path.basename(ascend_driver_path)

    ret, paths = execute(
        "find {path} -name \"make-os-sd.sh\"".format(path=CURRENT_PATH))
    if not ret:
        print("[ERROR] Can not find make_os_sd.sh in current path")
        return False

    ret, paths = execute(
        "find {path} -name \"ubuntu*server*arm*.iso\" -o -name \"*Euler*aarch64*.iso\"".format(path=CURRENT_PATH))
    if not ret or not paths[0]:
        print("[ERROR] Can not find iso package in current path")
        return False
    if len(paths) > 1:
        print("[ERROR] Too many iso packages, please delete redundant packages.")
        return False
    ubuntu_path = paths[0]
    ubuntu_file_name = os.path.basename(ubuntu_path)

    print("Step: Start to make card in recover model. It need some time, please wait...")

    print("Command:")
    making_cover_cmd = MAKING_RECOVER_COMMAND.format(path=CURRENT_PATH, pkg_path=CURRENT_PATH,
                                                    ubuntu_file_name=ubuntu_file_name)
    print(making_cover_cmd)
    try:
        subprocess.run(making_cover_cmd, shell=True)
    except KeyboardInterrupt:
        os.system('/usr/bin/stty echo')
        print('\nException: KeyboardInterrupt')
    except Exception as reason:
        os.system('/usr/bin/stty echo')
        print('\nException:', str(reason))

    ret = execute("grep Success {log_path}/{result}".format(log_path=log_path, result=MAKE_OS_RESULT))
    if not ret[0]:
        print("[ERROR] Making Card in recover model failed, \
            please check %s/make_os_sd.log for details!", log_path)
        return False

    return True


def process_local_installation(dev_name, card_type):
    ret = check_minirc_run_package()
    if not ret:
        return False

    confirm_tips = "Please make sure you have installed dependency packages:" + \
        "\n\t apt-get install -y qemu-user-static binfmt-support gcc-aarch64-linux-gnu \
        g++-aarch64-linux-gnu dosfstools parted kpartx\n" + \
        "Please input Y: continue, other to install them:"
    confirm = input(confirm_tips)
    confirm = confirm.strip()

    if confirm != "Y" and confirm != "y":
        return False

    ret, _ = execute("rm -rf {path}_log/*".format(path=SD_CARD_MAKING_PATH))
    if not ret:
        print("[ERROR] Failed to remove the log directory")

    ret, _ = execute("mkdir -p {path}_log".format(path=SD_CARD_MAKING_PATH))
    if not ret:
        print("[ERROR] Failed to create the log directory")

    log_path = "{path}_log".format(path=SD_CARD_MAKING_PATH)
    ret, paths = execute(
        "find {path} -name \"Ascend*310*driver*.*\"".format(path=CURRENT_PATH))
    if not ret:
        print("[ERROR] Can not find driver run package in current path")
        return False

    if len(paths) > 1:
        print(
            "[ERROR] Too many mini driver run packages, please delete redundant packages.")
        return False
    ascend_driver_path = paths[0]
    ascend_driver_file_name = os.path.basename(ascend_driver_path)

    ret, paths = execute(
        "find {path} -name \"make_os_sd.sh\"".format(path=CURRENT_PATH))
    if not ret:
        print("[ERROR] Can not find make_os_sd.sh in current path")
        return False

    ret, paths = execute(
        "find {path} -name \"ubuntu*server*arm*.iso\" -o -name \"*Euler*aarch64*.iso\"".format(path=CURRENT_PATH))
    if not ret or not paths[0]:
        print("[ERROR] Can not find iso package in current path")
        return False
    if len(paths) > 1:
        print("[ERROR] Too many iso packages, please delete redundant packages.")
        return False
    ubuntu_path = paths[0]
    ubuntu_file_name = os.path.basename(ubuntu_path)

    if card_type in CARD_TYPE_LIST:
        device_types = " or ".join([
            "M.2 SATA SSD" if item == "M.2" else item + " SSD" if item == "NVME" else item for item in CARD_TYPE_LIST])
        print("Step: Start to make {device_types}. It need some time, please wait...".format(device_types=device_types))
        print("Command:")
        making_sata_cmd = MAKING_SATA_COMMAND.format(path=CURRENT_PATH, dev_name=dev_name, pkg_path=CURRENT_PATH,
            ubuntu_file_name=ubuntu_file_name, log_path=log_path, card_type=card_type)
        print(making_sata_cmd)
        ret, _ = execute(making_sata_cmd)
        if not ret:
            print("[ERROR] Make {device_types} fail".format(device_types=device_types))
        ret = execute("grep Success {log_path}/{result}".format(log_path=log_path, result=MAKE_OS_RESULT))
        if not ret[0]:
            print("[ERROR] Make {device_types} fail, please check {log_path}/make_os_sd.log for details!".format(
                device_types=device_types, log_path=log_path))
            return False
    else:
        print("Step: Start to make SD Card. It need some time, please wait...")

        print("Command:")
        make_sd_cmd = MAKING_SD_CARD_COMMAND.format(path=CURRENT_PATH, dev_name=dev_name, pkg_path=CURRENT_PATH,
                                                    ubuntu_file_name=ubuntu_file_name, log_path=log_path)
        print(make_sd_cmd)
        ret, _ = execute(make_sd_cmd)
        if not ret:
            print("[ERROR] Making SD Card failed")
        ret = execute("grep Success {log_path}/{result}".format(log_path=log_path, result=MAKE_OS_RESULT))
        if not ret[0]:
            print("[ERROR] Making SD Card failed, please check %s/make_os_sd.log for details!", log_path)
            return False

    return True


def print_usage():
    print("Usage: ")
    print("\t[local   ]: python3 make_sd_card.py local [SD Name] [Card Type]")
    print("\t                 Use local given packages to make SD card/M.2 SATA SSD/NVME SSD/USB.")
    print("\t[recover ]: python3 make_sd_card.py recover")
    print("\t                 Use recover given packages to make card in recover model.")
    print("\t[restoreimg]:python3 make_sd_card.py mkrecoverimg [Card Type]")
    print("\t                 Use mkrecoverimg to make image package for restoring factory settings...")


def dev_name_check(dev_name):
    if re.search(r'[^a-zA-Z0-9\/]', dev_name):
        return False
    return True


def main():
    '''sd card making'''
    command = ""
    dev_name = ""
    card_type = ""

    if (len(sys.argv) >= 2):
        command = sys.argv[1]

    if command == COMMAND_MKRECOVERIMG:
        if (len(sys.argv) >= 3):
            card_type = sys.argv[2]
    else:
        if (len(sys.argv) >= 3):
            dev_name = sys.argv[2]

        if (len(sys.argv) >= 4):
            card_type = sys.argv[3]

    if not dev_name_check(dev_name):
        print("[ERROR] Illegal device")
        exit(-1)

    if command == COMMAND_LOCAL and len(sys.argv) == 3:
        print("Begin to make SD Card...")
    elif command == COMMAND_RECOVER and len(sys.argv) == 2:
        print("Begin to make Card in recover model...")
    elif command == COMMAND_MKRECOVERIMG and len(sys.argv) == 3:
        print("Begin to make Image package for restoring factory settings...")
    elif command == COMMAND_LOCAL and len(sys.argv) == 4 and card_type == "USB":
        print("Begin to make USB...")
    elif command == COMMAND_LOCAL and len(sys.argv) == 4 and card_type in SSD_CARD_TYPE:
        print("Begin to make M.2 SATA SSD..." if card_type == "M.2" else "Begin to make NVME SSD...")
    else:
        print("Invalid Command!")
        print_usage()
        exit(-1)

    if command == COMMAND_LOCAL:
        ret = check_sd(dev_name)
        if not ret:
            exit(-1)

    ssd_recoverimg_flag = "no"
    if card_type in SSD_CARD_TYPE and command == COMMAND_MKRECOVERIMG:
        ssd_recoverimg_flag = "yes"
    if ssd_recoverimg_flag == "no":
        ret = subprocess.run(["bash", PRECONFIG_PATH, "check"], shell=False).returncode
        if not ret:
            print("preconfig success.")
        else:
            print("preconfig failed!")
            exit(1)

    if command == COMMAND_LOCAL:
        result = process_local_installation(dev_name, card_type)
    elif command == COMMAND_MKRECOVERIMG:
        dev_name = "vdisk"
        result = process_local_installation(dev_name, card_type)
    else:
        result = process_recover_installation()

    if result:
        print("Make Card successfully!")
        exit(0)
    else:
        exit(-1)


if __name__ == '__main__':
    main()
