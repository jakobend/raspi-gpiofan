#!/bin/bash

name="pwmfan";
config_file="/etc/${name}.conf";

fahrenheit=0;
mintemp=;
maxtemp=;
hysteresis=;

period=40000;
minduty=60;
maxduty=100;
startduty=80;
starttime=1;

pwmchip=0;
pwm=0;
interval=5;
spin=0;
idle=0;

verbose=0;
syslog=0;
dry=0;

# Default temperatures
default_mintemp_c=50;
default_maxtemp_c=75;
default_hysteresis_c=5;
default_mintemp_f=122;
default_maxtemp_f=167;
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
    echo "Usage: ${name}.sh [-h] [-v] [-s] [-f] [-I] [-t mintemp] [-T maxtemp] [-h hysteresis] [-d minduty] [-D maxduty] [-p pwm] [-P period] [-i interval] [-s seconds]";
}

print_help() {
    print_usage;
    cat << EOF
Options:
    -h, --help          Print this help message and exit
    -v, --verbose       Enable verbose logging
    -s, --syslog        Prepend syslog levels to logging messages
    -f, --fahrenheit    Enter degrees in fahrenheit instead of celsius
    -I, --idle          Keep fan spinning at the lower duty cycle limit instead of disabling
    --dry               Never actually touch the PWM device
    -t, --mintemp N     Set lower temperature limit
    -T, --maxtemp N     Set upper temperature limit
    -h, --hysteresis N  Disable fan at this many degrees below the lower temperature limit
    -d, --minduty N     Set lower duty cycle in percents
    -D, --maxduty N     Set upper duty cycle in percents
    -P, --period N      Set PWM period in nanoseconds
    -c, --pwmchip N     PWM chip number of the fan driver
    -p, --pwm N         PWM device number of the fan driver
    -i, --interval N    Interval between check cycles, in seconds
    -S, --spin N        On start up, enable the fan for the given number of seconds
    --startduty         When fan changes from disabled to enabled, start with this duty cycle
    --starttime           for this many seconds
Configuration is read from ${config_file}.
EOF
}

set_duty() {
    if [[ $1 -eq 0 ]]; then
        if [ ! -d "${pwm_device_dir}" ]; then
            log_info "PWM device not exported";
            return 1;
        fi

        if [[ `cat "${pwm_device_dir}/enable"` -eq 1 ]]; then
            log_info "Disabling fan at PWM ${pwm}";
            echo "0" > "${pwm_device_dir}/enable";
        fi
    else
        local duty_ns=$(($1*(${period}/100)));
        if [[ `cat "${pwm_device_dir}/enable"` -eq 0 ]]; then
            if [[ "${startduty}" -ge $1 ]]; then
                local startduty_ns=$((${startduty}*(${period}/100)))
                echo "${startduty_ns}" > "${pwm_device_dir}/duty_cycle";
                log_info "Enabling fan at PWM ${pwm} with ${startduty}% (${startduty_ns} ns) start duty cycle for ${starttime} s";
                echo "1" > "${pwm_device_dir}/enable";
                sleep $starttime;
                log_debug "Setting fan duty cycle to $1% (${duty_ns} ns)"
                echo "${duty_ns}" > "${pwm_device_dir}/duty_cycle";
            else
                log_info "Enabling fan at PWM ${pwm} with $1% (${duty_ns} ns) duty cycle";
                echo "${duty_ns}" > "${pwm_device_dir}/duty_cycle";
                echo "1" > "${pwm_device_dir}/enable";
            fi
        else
            if [[ `cat "${pwm_device_dir}/duty_cycle"` -ne "$(($1*(${period}/100)))" ]]; then
                log_debug "Setting fan duty cycle to $1% (${duty_ns} ns)"
                echo "${duty_ns}" > "${pwm_device_dir}/duty_cycle";
            fi
        fi
    fi
}

setup() {
    # PWM might not be available yet
    # We could handle this with systemd requirements but that's not as flexible
    # and would require us to specify the pwmchip to use in the service.
    log_debug "Waiting for PWM to be ready";
    while [ ! -f "${export_device}" ]; do
        sleep 0.2;
    done

    if [ ! -d "${pwm_device_dir}" ]; then
        log_debug "Exporting PWM ${pwm}";
        echo "${pwm}" > "${export_device}";
        echo "${period}" > "${pwm_device_dir}/period";
    fi
}

cleanup() {
    if [ -d "${pwm_device_dir}" ]; then
        set_duty 0;
        log_debug "Unexporting PWM ${pwm}";
        echo "${pwm}" > "${unexport_device}";
    fi
    
    if [[ ${dry} -ne 0 ]]; then
        rm ${pwm_device_dir}/enable;
        rm ${pwm_device_dir}/period;
        rm ${pwm_device_dir}/duty_cycle;
        rmdir ${pwm_device_dir};
    fi

    exit 0;
}

run() {
    if [[ ${fahrenheit} -ne 0 ]]; then
        local temp="$(((`cat "${temp_device}"`*9000/5000+32000)/1000))";
    else
        local temp="$((`cat "${temp_device}"`/1000))";
    fi
    log_debug "CPU temperature is at ${temp}°${temp_unit}";

    if [[ ${temp} -le ${mintemp} ]]; then
        if [[ ${idle} -ne 0 ]]; then
            set_duty ${minduty};
        elif [[ ${temp} -lt $((${mintemp}-${hysteresis})) || `cat "${pwm_device_dir}/enable"` -eq 0 ]]; then
            set_duty 0;
        fi
    elif [[ ${temp} -gt ${maxtemp} ]]; then
        set_duty ${maxduty};
    else
        set_duty $((
            ((${temp}-${mintemp})*100/(${maxtemp}-${mintemp}))
            *(${maxduty}-${minduty})/100
            +${minduty}
        ));
    fi

    sleep ${interval};
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
            -t|--mintemp) mintemp="$2"; shift; shift;;
            -T|--maxtemp) maxtemp="$2"; shift; shift;;
            -h|--hysteresis) hysteresis="$2"; shift; shift;;
            -d|--minduty) minduty="$2"; shift; shift;;
            -D|--maxduty) maxduty="$2"; shift; shift;;
            -c|--pwmchip) pwmchip="$2"; shift; shift;;
            -p|--pwm) pwm="$2"; shift; shift;;
            -P|--period) period="$2"; shift; shift;;
            -i|--interval) interval="$2"; shift; shift;;
            -S|--spin) spin="$2"; shift; shift;;
            --starttime) starttime="$2"; shift; shift;;
            --startduty) startduty="$2"; shift; shift;;
            -I|--idle) idle=1; shift;;
            -f|--fahrenheit) fahrenheit=1; shift;;
            -v|--verbose) verbose=1; shift;;
            -s|--syslog) syslog=1; shift;;
            --dry) dry=1; shift;;
            *) >&2 echo "Unknown option: $key"; print_usage; exit 1;;
        esac
    done

    # Set default temperatures
    if [[ ${fahrenheit} -ne 0 ]]; then
        mintemp=${mintemp:-${default_mintemp_f}};
        maxtemp=${maxtemp:-${default_maxtemp_f}};
        hysteresis=${hysteresis:-${default_hysteresis_f}};
        temp_unit="F";
    else
        mintemp=${mintemp:-${default_mintemp_c}};
        maxtemp=${maxtemp:-${default_maxtemp_c}};
        hysteresis=${hysteresis:-${default_hysteresis_c}};
        temp_unit="C";
    fi

    if [[ ${dry} -ne 0 ]]; then
        export_device="/dev/null";
        unexport_device="/dev/null";
        pwm_device_dir=$(mktemp -d);
        echo "0" > ${pwm_device_dir}/enable;
        echo "0" > ${pwm_device_dir}/period;
        echo "0" > ${pwm_device_dir}/duty_cycle;
        log_info "Running dry with virtual PWM at ${pwm_device_dir}";
    else
        export_device="/sys/class/pwm/pwmchip${pwmchip}/export";
        unexport_device="/sys/class/pwm/pwmchip${pwmchip}/unexport";
        pwm_device_dir="/sys/class/pwm/pwmchip${pwmchip}/pwm${pwm}";
    fi
    temp_device="/sys/class/thermal/thermal_zone0/temp"

    log_info "Temperature limits: ${mintemp}°${temp_unit} to ${maxtemp}°${temp_unit}; Hysteresis: ${hysteresis}°${temp_unit}";
    log_info "Duty cycle limits: ${minduty}% to ${maxduty}%; Period: ${period} ns ($((1000000/${period})) kHz)";
    log_info "PWM device: ${pwm} on chip ${pwmchip}; Check interval: ${interval}s"
    setup;
    trap cleanup EXIT TERM INT;
    if [[ ${spin} -ne 0 ]]; then
        set_duty 100;
        sleep ${spin};
        # Hysteresis might keep fan at 100% longer than spin, so disable it again
        set_duty 0;
    fi
    run;
}

main $*;
