#!/bin/bash

name="gpiofan";
config_file="/etc/${name}.conf";

fahrenheit=0;
treshold=;
hysteresis=;

pin=18;
interval=5;
spin=0;

verbose=0;
syslog=0;
dry=0;

# Default temperatures
default_treshold_c=70;
default_hysteresis_c=5;
default_treshold_f=158;
default_hysteresis_f=9;

log_debug() {
    if [[ ${verbose} -ne 0 ]]; then
        if [[ ${syslog} -ne 0 ]]; then
            echo "<7>$*";
        else
            echo "$*";
        fi
    fi
}
log_info() {
    if [[ ${syslog} -ne 0 ]]; then
        echo "<6>$*";
    else
        echo "$*";
    fi
}

print_usage() {
    echo "Usage: ${name}.sh [-h] [-v] [-s] [-f] [-t treshold] [-H hysteresis] [-p pin] [-i interval] [-s seconds]";
}

print_help() {
    print_usage;
    cat << EOF
Options:
    -h, --help          Print this help message and exit
    -d, --dry           Never actually touch the pin device
    -v, --verbose       Enable verbose logging
    -s, --syslog        Prepend syslog levels to logging messages
    -f, --fahrenheit    Enter degrees in fahrenheit instead of celsius
    -t, --treshold N    Enable fan at this temperature
    -H, --hysteresis N  Disable fan at this many degrees below treshold
    -p, --pin N         Pin number of the fan driver
    -i, --interval N    Interval between check cycles, in seconds
    -S, --spin N        On start up, enable the fan for the given number of seconds
Configuration is read from ${config_file}.
EOF
}

enable_fan() {
    if [[ `cat "${pin_device_dir}/value"` -eq 0 ]]; then
        log_info "Enabling fan at GPIO ${pin}";
        echo "1" > "${pin_device_dir}/value";
    fi
}

disable_fan() {
    if [[ `cat "${pin_device_dir}/value"` -eq 1 ]]; then
        log_info "Disabling fan at GPIO ${pin}";
        echo "0" > "${pin_device_dir}/value";
    fi
}

setup() {
    if [ ! -d "${pin_device_dir}" ]; then
        log_debug "Exporting GPIO ${pin}";
        echo "${pin}" > "${export_device}";
    fi
    log_debug "Setting GPIO ${pin} to output";
    echo "out" > "${pin_device_dir}/direction";
}

cleanup() {
    if [ -d "${pin_device_dir}" ]; then
        disable_fan;
        log_debug "Unexporting GPIO ${pin}.";
        echo "${pin}" > "${unexport_device}";
    fi
    
    if [[ ${dry} -ne 0 ]]; then
        rm ${pin_device_dir}/value;
        rm ${pin_device_dir}/direction;
        rmdir ${pin_device_dir};
    fi

    exit 0;
}

run() {
    time_now=`date +%s`;
    if [ -z ${last} ]; then
        time_last=`date +%s`;
    fi

    if [[ ${fahrenheit} -ne 0 ]]; then
        temp="$(((`cat "${temp_device}"`*9000/5000+32000)/1000))";
    else
        temp="$((`cat "${temp_device}"`/1000))";
    fi
    log_debug "CPU temperature is at ${temp}°${temp_unit}";

    if [[ ${temp} -ge ${treshold} ]]; then
        enable_fan;
    elif [[ ${temp} -le ${lower_treshold} ]]; then
        disable_fan;
    fi

    time_last=`date +%s`;
    if [[ ! $((time_now-time_last+interval+1)) -lt $((interval)) ]]; then
        sleep $((time_now-time_last+interval));
    fi

    run;
}

main() {
    # Read configuration file
    if [ -f "${config_file}" ]; then
        . ${config_file};
    fi

    # Read options
    while [[ $# -gt 0 ]]; do
        key="$1"
        case $key in
            -h|--help) print_help; exit 0;;
            -t|--treshold) treshold="$2"; shift; shift;;
            -H|--hysteresis) hysteresis="$2"; shift; shift;;
            -p|--pin) pin="$2"; shift; shift;;
            -i|--interval) interval="$2"; shift; shift;;
            -S|--spin) spin="$2"; shift; shift;;
            -f|--fahrenheit) fahrenheit=1; shift;;
            -v|--verbose) verbose=1; shift;;
            -s|--syslog) syslog=1; shift;;
            -d|--dry) dry=1; shift;;
            *) >&2 echo "Unknown option: $key"; print_usage; exit 1;;
        esac
    done

    # Set default temperatures
    if [[ ${fahrenheit} -ne 0 ]]; then
        treshold=${treshold:-${default_treshold_f}};
        hysteresis=${hysteresis:-${default_hysteresis_f}};
        temp_unit="F";
    else
        treshold=${treshold:-${default_treshold_c}};
        hysteresis=${hysteresis:-${default_hysteresis_c}};
        temp_unit="C";
    fi
    lower_treshold=$((${treshold}-${hysteresis}));

    if [[ ${dry} -ne 0 ]]; then
        export_device="/dev/null";
        unexport_device="/dev/null";
        pin_device_dir=$(mktemp -d);
        echo "0" > ${pin_device_dir}/value;
        echo "in" > ${pin_device_dir}/direction;
        log_info "Running dry with virtual pin at ${pin_device_dir}";
    else
        export_device="/sys/class/gpio/export";
        unexport_device="/sys/class/gpio/unexport";
        pin_device_dir="/sys/class/gpio/gpio${pin}";
    fi
    temp_device="/sys/class/thermal/thermal_zone0/temp"

    log_info "Treshold: ${treshold}°${temp_unit}; Hysteresis: ${hysteresis}°${temp_unit}: Lower Treshold: ${lower_treshold}°${temp_unit}";
    log_info "GPIO pin: ${pin}; Check interval: ${interval}s"
    setup;
    trap cleanup EXIT TERM INT;
    if [[ ${spin} -ne 0 ]]; then
        enable_fan;
        sleep ${spin};
        # Hysteresis might keep fan at 100% longer than spin, so disable it again
        disable_fan;
    fi
    run;
}

main $*;
