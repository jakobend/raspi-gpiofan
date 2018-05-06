#!/bin/bash

name="gpiofan"

max_temp=${GPIOFAN_TRESHOLD:-70};
hysteresis=${GPIOFAN_HYSTERESIS:-2};
min_temp=$((${max_temp}-${hysteresis}))

pin_id=${GPIOFAN_PIN:-18};
run_interval=${GPIOFAN_INTERVAL:-5};

export_device="/sys/class/gpio/export"
unexport_device="/sys/class/gpio/unexport"
pin_device_dir="/sys/class/gpio/gpio${pin_id}"
temp_device="/sys/class/thermal/thermal_zone0/temp"

enable_fan() {
    if [[ `cat "${pin_device_dir}/value"` -eq 0 ]]; then
        echo "<7>Setting GPIO ${pin_id} to high.";
        echo "1" > "${pin_device_dir}/value";
    fi
}

disable_fan() {
    if [[ `cat "${pin_device_dir}/value"` -eq 1 ]]; then
        echo "<7>Setting GPIO ${pin_id} to low.";
        echo "0" > "${pin_device_dir}/value";
    fi
}

setup() {
    if [ ! -d "${pin_device_dir}" ]; then
        echo "<7>Exporting GPIO ${pin_id}.";
        echo "${pin_id}" > "${export_device}";
    fi
    echo "<7>Setting direction of GPIO ${pin_id} to output.";
    echo "out" > "${pin_device_dir}/direction";
}

run() {
    now=`date +%s`;
    if [ -z ${last} ]; then
        last=`date +%s`;
    fi

    temp="$((`cat "${temp_device}"`/1000))"
    if [[ ${temp} -ge ${max_temp} ]]; then
        enable_fan;
    elif [[ ${temp} -le ${min_temp} ]]; then
        disable_fan;
    fi

    last=`date +%s`;
    if [[ ! $((now-last+run_interval+1)) -lt $((run_interval)) ]]; then
        sleep $((now-last+run_interval));
    fi

    run;
}

cleanup() {
    if [ -d "${pin_device_dir}" ]; then
        echo "<7>Unexporting GPIO ${pin_id}.";
        echo "${pin_id}" > "${unexport_device}";
    fi
}

echo "<6>Treshold ${max_temp}C, ${hysteresis}C hysteresis, pin ${pin_id}, ${run_interval}s interval."
setup;
trap cleanup EXIT;
run;
