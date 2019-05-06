#!/bin/bash

target=$1;
if [[ "${target}" != "pwm" && "${target}" != "gpio" ]]; then
    echo "usage: install.sh pwm|gpio";
    exit 1;
fi

if [[ $(id -u) -ne 0 ]]; then
    echo "This script must be run as root.";
    exit 1;
fi

# TODO: Is there a better way to do this?
# How to handle read-only file systems?
if [ -d "/storage/.config" ]; then
    # OpenELEC and derivates
    method="systemd";
    systemd_service_path="/storage/.config/system.d/${target}fan.service";
    script_path="/storage/.config/${target}fan.sh";
    conf_path="/storage/.config/${target}fan.conf";
elif [ `ps --no-headers -o comm 1` == "systemd" ]; then
    # Generic SystemD
    method="systemd";
    systemd_service_path="/etc/systemd/system/${target}fan.service";
    script_path="/usr/local/bin/${target}fan.sh";
    conf_path="etc/{target}fan.conf";
elif [ -d "/etc/crontab" ]; then
    # Cron fallback
    method="cron";
    cron_entry_path="/etc/crontab/${target}fan";
    script_path="/usr/local/bin/${target}fan.sh";
    conf_path="/etc/${target}fan.conf";
else
    # TODO: rc.local or init.d?
    echo "Automatic installation is not supported on this system.";
    exit 1;
fi

install() {
    if [ ! -f "${conf_path}" ]; then
        echo "Installing ./${target}fan.conf.example to ${conf_path}";
        cp "./${target}fan.conf.example" "${conf_path}";
        chown "$USER" "${conf_path}";
        chmod 700 "${conf_path}";
    else
        echo "${conf_path} already exists, skipping.";
    fi

    if [ ! -f "${script_path}" ]; then
        echo "Installing ./${target}fan.sh to ${script_path}";
        awk '{gsub(/config_file=\".*\"/,"config_file=\"'${conf_path}'\""); print;};' "./${target}fan.sh" > "${script_path}";
        chown "$USER" "${script_path}";
        chmod 700 "${script_path}";
    else
        echo "${script_path} exists, skipping.";
    fi

    if [[ "${method}" == "systemd" ]]; then
        if [ ! -f "${systemd_service_path}" ]; then
            echo "Installing SystemD service to ${systemd_service_path}";
            cat > "${systemd_service_path}" <<EOL
[Unit]
Description=${target} Fan Controller
Documentation=https://github.com/jakobend/raspi-gpiofan
Wants=local-fs.target
After=local-fs.target

[Service]
ExecStart=${script_path} -s

[Install]
WantedBy=basic.target
EOL
            echo "Enabling and starting service";
            systemctl daemon-reload;
            systemctl enable ${target}fan.service;
            systemctl start ${target}fan.service;
        else
            echo "${systemd_service_path} exists, skipping.";
        fi

    elif [[ "${method}" == "cron" ]]; then
        if [ ! -f "${script_path}" ]; then
            echo "@reboot root ${script_path} &" > ${cron_entry_path};
        else
            echo "${cron_entry_path} exists, skipping.";
        fi

        echo "Starting service";
        ${script_path} &
    fi
}

uninstall() {
    if [[ "${method}" == "systemd" ]]; then
        if [ -f "${systemd_service_path}" ]; then
            echo "Stopping and disabling service";
            systemctl stop ${target}fan.service;
            systemctl disable ${target}fan.service;
            systemctl daemon-reload;

            echo "Removing ${systemd_service_path}";
            rm "${systemd_service_path}";
        else
            echo "${systemd_service_path} does not exist, skipping.";
        fi
    elif [[ "${method}" == "cron" ]]; then
        if [ -f "${cron_entry_path}" ]; then
            echo "Removing ${cron_entry_path}";
            rm "${cron_entry_path}";
        else
            echo "${cron_entry_path} does not exist, skipping.";
        fi
        # TODO: Kill script?
        echo "Reboot or terminate ${target}fan.sh manually.";
    fi

    if [ -f "${script_path}" ]; then
        echo "Removing ./${target}fan.sh from ${script_path}";
        rm ${script_path};
    else
        echo "${script_path} does not exist, skipping.";
    fi
}

echo "This script will (un)install ${target}fan.sh on your system using ${method}."
read -p "Install/uninstall/abort (i/u/*)? " choice
case "$choice" in 
  i|I ) install;;
  u|U ) uninstall;;
  * ) exit 0;;
esac

echo "Done.";
exit 0;
