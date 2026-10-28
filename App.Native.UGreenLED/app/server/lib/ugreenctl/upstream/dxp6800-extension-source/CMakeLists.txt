cmake_minimum_required(VERSION 3.20)

project(ugreenctl VERSION 0.2.0 LANGUAGES C)

if(NOT CMAKE_SYSTEM_NAME STREQUAL "Linux")
  message(FATAL_ERROR "ugreenctl requires Linux hardware interfaces.")
endif()

# A Windows-hosted Linux cross-build must embed a Linux plugin directory.
# CMake otherwise defaults to a Windows Program Files installation prefix.
if(CMAKE_CROSSCOMPILING AND CMAKE_HOST_WIN32)
  if(CMAKE_INSTALL_PREFIX_INITIALIZED_TO_DEFAULT)
    set(CMAKE_INSTALL_PREFIX "/usr/local" CACHE PATH "Linux installation prefix" FORCE)
  endif()
  if(NOT CMAKE_INSTALL_PREFIX MATCHES "^/" OR CMAKE_INSTALL_PREFIX MATCHES "[:\\\\]")
    message(FATAL_ERROR "Linux cross-builds require a Linux absolute CMAKE_INSTALL_PREFIX, for example /usr/local.")
  endif()
endif()

if(CMAKE_SYSTEM_PROCESSOR MATCHES "^(x86_64|amd64|i[3-6]86)$")
  set(UGREENCTL_SUPERIO_SOURCE superio/it86x.c)
elseif(CMAKE_SYSTEM_PROCESSOR MATCHES "^(aarch64|arm64)$")
  set(UGREENCTL_SUPERIO_SOURCE superio/it86x_unavailable.c)
else()
  message(FATAL_ERROR "ugreenctl supports Linux x86/x86_64 and ARM64 hardware only.")
endif()

include(GNUInstallDirs)
include(CTest)

set(CMAKE_C_STANDARD 11)
set(CMAKE_C_STANDARD_REQUIRED ON)
set(CMAKE_C_EXTENSIONS OFF)

add_library(ugreenctl_core STATIC
  core/loader.c
)
target_include_directories(ugreenctl_core PUBLIC ${CMAKE_CURRENT_SOURCE_DIR}/include)
target_compile_definitions(ugreenctl_core PRIVATE
  UGREENCTL_DEFAULT_MODEL_DIR="${CMAKE_INSTALL_FULL_LIBDIR}/ugreenctl/models"
)
target_link_libraries(ugreenctl_core PRIVATE dl)
set_target_properties(ugreenctl_core PROPERTIES POSITION_INDEPENDENT_CODE ON)

add_library(ugreenctl_hardware STATIC
  ${UGREENCTL_SUPERIO_SOURCE}
  core/identity.c
  fan/it8613_direct.c
  fan/it8613_hwmon.c
  fan/it8613_fan.c
  fan/it8613_dx4600.c
  fan/it8613_dxp4800.c
  fan/it8613_dxp4800s.c
  fan/it8613_dxp480t.c
  fan/it8613_dxp6800pro.c
  fan/it8613_dxp6800plus.c
  fan/it8613_dxp6800.c
  fan/thermal_curve.c
  power/it8613_power.c
  power/rtc_wake.c
  models/wake_profiles.c
  network/wol_interface.c
  network/wol.c
  network/wol_dx4600.c
  network/wol_dxp4800.c
  network/wol_dxp4800plus.c
  network/wol_dxp4800s.c
  network/wol_dxp480tplus.c
  network/wol_dxp6800pro.c
  network/wol_dxp6800plus.c
  led/led.c
  led/led_n76_protocol.c
  led/led_protocol.c
  led/led_sysfs.c
  led/led_gpio.c
  led/led_service.c
  led/led_cs201x.c
  models/led_profiles.c
  disk/disk.c
  disk/firmware_profiles.c
  ec/ec.c
)
target_include_directories(ugreenctl_hardware PUBLIC
  ${CMAKE_CURRENT_SOURCE_DIR}/include
  ${CMAKE_CURRENT_SOURCE_DIR}
)
set_target_properties(ugreenctl_hardware PROPERTIES POSITION_INDEPENDENT_CODE ON)

add_library(ugreenctl_cli STATIC core/hardware_cli.c core/wake_cli.c)
target_include_directories(ugreenctl_cli PUBLIC
  ${CMAKE_CURRENT_SOURCE_DIR}/include
  ${CMAKE_CURRENT_SOURCE_DIR}
)
target_link_libraries(ugreenctl_cli PUBLIC ugreenctl_hardware ugreenctl_core)

add_executable(ugreenctl core/main.c)
target_include_directories(ugreenctl PRIVATE
  ${CMAKE_CURRENT_SOURCE_DIR}/include
  ${CMAKE_CURRENT_SOURCE_DIR}
)
target_link_libraries(ugreenctl PRIVATE ugreenctl_core ugreenctl_cli dl)

add_executable(ugreen_leds_cli core/led_compat_main.c)
target_link_libraries(ugreen_leds_cli PRIVATE ugreenctl_cli)

add_executable(ugreenctl-ledd core/led_daemon_main.c)
target_link_libraries(ugreenctl-ledd PRIVATE ugreenctl_hardware)

add_executable(ugreenctl-fand core/fan_daemon.c)
target_include_directories(ugreenctl-fand PRIVATE
  ${CMAKE_CURRENT_SOURCE_DIR}/include
  ${CMAKE_CURRENT_SOURCE_DIR}
)
target_link_libraries(ugreenctl-fand PRIVATE ugreenctl_hardware)

foreach(target ugreenctl_core ugreenctl_hardware ugreenctl_cli ugreenctl ugreenctl-fand ugreen_leds_cli ugreenctl-ledd)
  target_compile_options(${target} PRIVATE -Wall -Wextra -Wpedantic)
endforeach()

function(add_model_plugin target source)
  add_library(${target} MODULE ${source})
  target_include_directories(${target} PRIVATE
    ${CMAKE_CURRENT_SOURCE_DIR}/include
    ${CMAKE_CURRENT_SOURCE_DIR}
  )
  target_link_libraries(${target} PRIVATE ugreenctl_hardware)
  target_compile_options(${target} PRIVATE -Wall -Wextra -Wpedantic)
  set_target_properties(${target} PROPERTIES
    PREFIX ""
    LIBRARY_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/models"
  )
endfunction()

add_model_plugin(dx4600 models/dx4600.c)
add_model_plugin(dxp4800plus models/dxp4800plus.c)
add_model_plugin(dxp4800s models/dxp4800s.c)
add_model_plugin(dxp480tplus models/dxp480tplus.c)
add_model_plugin(dxp2800 models/unsupported_model.c)
target_compile_definitions(dxp2800 PRIVATE MODEL_ID="dxp2800" MODEL_NAME="UGREEN DXP2800" MODEL_DMI_NAME="DXP2800")
add_model_plugin(dxp4800 models/dxp4800.c)
add_model_plugin(dxp6800pro models/dxp6800pro.c)
add_model_plugin(dxp6800plus models/dxp6800plus.c)
add_model_plugin(dxp6800 models/dxp6800.c)
add_model_plugin(dxp8800plus models/unsupported_model.c)
target_compile_definitions(dxp8800plus PRIVATE MODEL_ID="dxp8800plus" MODEL_NAME="UGREEN DXP8800 Plus" MODEL_DMI_NAME="DXP8800 Plus")

install(TARGETS ugreenctl ugreenctl-fand ugreenctl-ledd RUNTIME DESTINATION ${CMAKE_INSTALL_BINDIR})
# Keep the compatibility name opt-in so installation cannot overwrite an existing CLI.
option(UGREENCTL_INSTALL_LED_COMPAT "Install the ugreen_leds_cli compatibility executable" OFF)
if(UGREENCTL_INSTALL_LED_COMPAT)
  install(TARGETS ugreen_leds_cli RUNTIME DESTINATION ${CMAKE_INSTALL_BINDIR})
endif()
install(TARGETS dx4600 dxp2800 dxp4800 dxp4800plus dxp4800s dxp480tplus dxp6800pro dxp6800plus dxp6800 dxp8800plus
  LIBRARY DESTINATION ${CMAKE_INSTALL_LIBDIR}/ugreenctl/models
)
install(FILES
  README.md
  README.zh-CN.md
  docs/HARDWARE_SUPPORT.md
  docs/COMPATIBILITY.md
  docs/COMPATIBILITY.zh-CN.md
  docs/DXP4800S_REVERSE_ENGINEERING.md
  docs/DXP4800_REVERSE_ENGINEERING.md
  docs/DX4600_REVERSE_ENGINEERING.zh-CN.md
  docs/WOL_FIRMWARE_EVIDENCE.md
  docs/WOL_FIRMWARE_EVIDENCE.zh-CN.md
  docs/ALL_MODELS_WAKE_EVIDENCE.zh-CN.md
  docs/SCHEDULED_POWER_FIRMWARE_EVIDENCE.md
  docs/DXP4800S_REVERSE_ENGINEERING.zh-CN.md
  docs/DXP480T_PLUS_FAN_REVERSE_ENGINEERING.md
  docs/DXP6800_PRO_REVERSE_ENGINEERING.md
  docs/DXP6800_1.20_FIRMWARE_CHECK.zh-CN.md
  docs/DXP4800S_1.19.md
  docs/DXP4800S_INTAKE.md
  docs/DX4600_INTAKE.md
  docs/FAN_CURVE.md
  THIRD_PARTY_NOTICES.md
  docs/NEW_MODEL_TEMPLATE.md
  models/compatibility.json
  DESTINATION ${CMAKE_INSTALL_DOCDIR}
)
install(FILES led/LICENSE.upstream-led DESTINATION ${CMAKE_INSTALL_DOCDIR}/led)
install(FILES disk/NOTICE.md DESTINATION ${CMAKE_INSTALL_DOCDIR}/disk)
install(FILES scripts/ugreenctl-ledd.service DESTINATION ${CMAKE_INSTALL_DOCDIR}/examples)
install(FILES scripts/ugreenctl-ledd-gt.service DESTINATION ${CMAKE_INSTALL_DOCDIR}/examples)
install(FILES scripts/ugreenctl-startup.service DESTINATION ${CMAKE_INSTALL_DOCDIR}/examples)
install(PROGRAMS scripts/collect-disk-evidence.sh DESTINATION ${CMAKE_INSTALL_DOCDIR}/examples)
install(PROGRAMS scripts/collect-led-evidence.sh DESTINATION ${CMAKE_INSTALL_DOCDIR}/examples)
install(PROGRAMS scripts/ugreenctl-startup.py DESTINATION ${CMAKE_INSTALL_DOCDIR}/examples)
install(FILES models/official-products.json DESTINATION ${CMAKE_INSTALL_DOCDIR}/models)
install(FILES
  integration/llled/ac-recovery/README.zh-CN.md
  integration/llled/ac-recovery/llled-startup-persistence.patch
  integration/llled/ac-recovery/source-hashes.json
  DESTINATION ${CMAKE_INSTALL_DOCDIR}/integration/llled/ac-recovery
)
install(FILES
  docs/LED_CONTROL.zh-CN.md
  docs/LINUX_DEPLOYMENT.zh-CN.md
  docs/DISK_MAPPING_FIRMWARE.zh-CN.md
  docs/ALL_MODELS_FIRMWARE_INTAKE.zh-CN.md
  docs/ALL_MODELS_LED_EVIDENCE.zh-CN.md
  docs/ALL_MODELS_DISK_EVIDENCE.zh-CN.md
  docs/FIRMWARE_RUNTIME_TRACE_20261026.zh-CN.md
  docs/DH2100_FIRMWARE_SEARCH.zh-CN.md
  docs/DXP2800_GT_LED_REVERSE.zh-CN.md
  docs/LED_EVIDENCE_COLLECTION.zh-CN.md
  docs/ALMIGHTY_STATUS.zh-CN.md
  docs/BUILD_REPRODUCIBILITY.zh-CN.md
  docs/AC_RECOVERY_PERSISTENCE.zh-CN.md
  docs/N76_DIRECT_CONTROL.zh-CN.md
  docs/DX4600_REVERSE_ENGINEERING.zh-CN.md
  DESTINATION ${CMAKE_INSTALL_DOCDIR}/docs
)

if(BUILD_TESTING)
  # Packaging runs on the build host and does not execute inspected ELF data.
  find_package(Python3 3.10 QUIET COMPONENTS Interpreter)
  if(Python3_Interpreter_FOUND)
    add_test(NAME package-runtime COMMAND ${Python3_EXECUTABLE} ${CMAKE_CURRENT_SOURCE_DIR}/tests/test_package_runtime.py)
    add_test(NAME package-policy COMMAND ${Python3_EXECUTABLE} ${CMAKE_CURRENT_SOURCE_DIR}/tests/test_package_almighty.py)
    add_test(NAME startup-state COMMAND ${Python3_EXECUTABLE} ${CMAKE_CURRENT_SOURCE_DIR}/tests/test_startup_state.py)
  endif()
  add_test(NAME cli-help COMMAND ugreenctl --help)
  add_test(NAME led-cli-help COMMAND ugreenctl led --help)
  add_test(NAME led-compat-help COMMAND ugreen_leds_cli --help)
  add_test(NAME led-holder-help COMMAND ugreenctl-ledd --help)
  add_executable(test-led tests/test_led.c tests/test_led_gpio.c tests/test_led_n76.c led/led.c led/led_n76_protocol.c led/led_protocol.c led/led_sysfs.c led/led_gpio.c led/led_service.c led/led_cs201x.c models/led_profiles.c core/identity.c)
  target_include_directories(test-led PRIVATE ${CMAKE_CURRENT_SOURCE_DIR} ${CMAKE_CURRENT_SOURCE_DIR}/include)
  target_compile_definitions(test-led PRIVATE UGREENCTL_LED_TESTING)
  target_compile_options(test-led PRIVATE -Wall -Wextra -Wpedantic)
  add_test(NAME led COMMAND test-led)
  add_executable(test-led-service tests/test_led_service.c led/led_service.c)
  target_compile_definitions(test-led-service PRIVATE UGREENCTL_LED_SERVICE_TESTING)
  target_compile_options(test-led-service PRIVATE -Wall -Wextra -Wpedantic)
  target_link_libraries(test-led-service PRIVATE ugreenctl_hardware)
  add_test(NAME led-holder COMMAND test-led-service)
  add_executable(test-led-cs201x tests/test_led_cs201x.c led/led_cs201x.c)
  target_include_directories(test-led-cs201x PRIVATE ${CMAKE_CURRENT_SOURCE_DIR} ${CMAKE_CURRENT_SOURCE_DIR}/include)
  target_compile_definitions(test-led-cs201x PRIVATE UGREENCTL_LED_TESTING)
  target_compile_options(test-led-cs201x PRIVATE -Wall -Wextra -Wpedantic)
  add_test(NAME led-cs201x COMMAND test-led-cs201x)
  add_executable(test-disk-mapping tests/test_disk_mapping.c disk/disk.c disk/firmware_profiles.c)
  target_include_directories(test-disk-mapping PRIVATE ${CMAKE_CURRENT_SOURCE_DIR} ${CMAKE_CURRENT_SOURCE_DIR}/include)
  target_compile_options(test-disk-mapping PRIVATE -Wall -Wextra -Wpedantic)
  add_test(NAME disk-mapping COMMAND test-disk-mapping)
  add_executable(test-identity tests/test_identity.c core/identity.c)
  target_include_directories(test-identity PRIVATE ${CMAKE_CURRENT_SOURCE_DIR})
  target_compile_options(test-identity PRIVATE -Wall -Wextra -Wpedantic)
  add_test(NAME identity COMMAND test-identity)
  add_executable(test-hardware-cli tests/test_hardware_cli.c)
  target_link_libraries(test-hardware-cli PRIVATE ugreenctl_cli)
  target_compile_options(test-hardware-cli PRIVATE -Wall -Wextra -Wpedantic)
  add_test(NAME hardware-cli COMMAND test-hardware-cli)
  add_executable(test-it8613-hwmon tests/test_it8613_hwmon.c)
  target_include_directories(test-it8613-hwmon PRIVATE
    ${CMAKE_CURRENT_SOURCE_DIR}/include
    ${CMAKE_CURRENT_SOURCE_DIR}
  )
  target_link_libraries(test-it8613-hwmon PRIVATE ugreenctl_hardware)
  target_compile_options(test-it8613-hwmon PRIVATE -Wall -Wextra -Wpedantic)
  add_test(NAME it8613-hwmon COMMAND test-it8613-hwmon)
  add_executable(test-it8613-direct
    tests/test_it8613_direct.c
    fan/it8613_direct.c
  )
  target_include_directories(test-it8613-direct PRIVATE
    ${CMAKE_CURRENT_SOURCE_DIR}/include
    ${CMAKE_CURRENT_SOURCE_DIR}
  )
  target_compile_options(test-it8613-direct PRIVATE -Wall -Wextra -Wpedantic)
  add_test(NAME it8613-direct COMMAND test-it8613-direct)
  add_executable(test-it8613-power
    tests/test_it8613_power.c
    power/it8613_power.c
  )
  target_include_directories(test-it8613-power PRIVATE
    ${CMAKE_CURRENT_SOURCE_DIR}/include
    ${CMAKE_CURRENT_SOURCE_DIR}
  )
  target_compile_options(test-it8613-power PRIVATE -Wall -Wextra -Wpedantic)
  add_test(NAME it8613-power COMMAND test-it8613-power)
  add_executable(test-it8613-dxp4800
    tests/test_it8613_dxp4800.c
    fan/it8613_dxp4800.c
  )
  target_include_directories(test-it8613-dxp4800 PRIVATE
    ${CMAKE_CURRENT_SOURCE_DIR}/include
    ${CMAKE_CURRENT_SOURCE_DIR}
  )
  target_compile_options(test-it8613-dxp4800 PRIVATE -Wall -Wextra -Wpedantic)
  add_test(NAME it8613-dxp4800 COMMAND test-it8613-dxp4800)
  add_executable(test-it8613-dxp4800s
    tests/test_it8613_dxp4800s.c
    fan/it8613_dxp4800s.c
  )
  target_include_directories(test-it8613-dxp4800s PRIVATE
    ${CMAKE_CURRENT_SOURCE_DIR}/include
    ${CMAKE_CURRENT_SOURCE_DIR}
  )
  target_compile_options(test-it8613-dxp4800s PRIVATE -Wall -Wextra -Wpedantic)
  add_test(NAME it8613-dxp4800s COMMAND test-it8613-dxp4800s)
  add_executable(test-it8613-dx4600
    tests/test_it8613_dx4600.c
    fan/it8613_dx4600.c
  )
  target_include_directories(test-it8613-dx4600 PRIVATE
    ${CMAKE_CURRENT_SOURCE_DIR}/include
    ${CMAKE_CURRENT_SOURCE_DIR}
  )
  target_compile_options(test-it8613-dx4600 PRIVATE -Wall -Wextra -Wpedantic)
  add_test(NAME it8613-dx4600 COMMAND test-it8613-dx4600)
  add_executable(test-dx4600-plugin
    tests/test_dx4600_plugin.c
    models/dx4600.c
  )
  target_include_directories(test-dx4600-plugin PRIVATE
    ${CMAKE_CURRENT_SOURCE_DIR}/include
    ${CMAKE_CURRENT_SOURCE_DIR}
  )
  target_compile_options(test-dx4600-plugin PRIVATE -Wall -Wextra -Wpedantic)
  add_test(NAME dx4600-plugin COMMAND test-dx4600-plugin)
  add_executable(test-wol-dxp4800
    tests/test_wol_dxp4800.c
    network/wol_dx4600.c
    network/wol_dxp4800.c
    network/wol_dxp4800plus.c
    network/wol_dxp4800s.c
    network/wol_dxp480tplus.c
    network/wol_dxp6800pro.c
  network/wol_dxp6800plus.c
  )
  target_include_directories(test-wol-dxp4800 PRIVATE
    ${CMAKE_CURRENT_SOURCE_DIR}/include
    ${CMAKE_CURRENT_SOURCE_DIR}
  )
  target_compile_options(test-wol-dxp4800 PRIVATE -Wall -Wextra -Wpedantic)
  add_test(NAME wol-dxp4800 COMMAND test-wol-dxp4800)
  add_executable(test-wol-runtime tests/test_wol_runtime.c)
  target_include_directories(test-wol-runtime PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}/include ${CMAKE_CURRENT_SOURCE_DIR})
  target_compile_options(test-wol-runtime PRIVATE -Wall -Wextra -Wpedantic -UNDEBUG)
  add_test(NAME wol-runtime COMMAND test-wol-runtime)
  add_executable(test-rtc-wake tests/test_rtc_wake.c)
  target_include_directories(test-rtc-wake PRIVATE
    ${CMAKE_CURRENT_SOURCE_DIR}/include
    ${CMAKE_CURRENT_SOURCE_DIR}
  )
  target_link_libraries(test-rtc-wake PRIVATE ugreenctl_hardware)
  target_compile_options(test-rtc-wake PRIVATE -Wall -Wextra -Wpedantic)
  add_test(NAME rtc-wake COMMAND test-rtc-wake)
  add_executable(test-it8613-dxp480t
    tests/test_it8613_dxp480t.c
    fan/it8613_dxp480t.c
  )
  target_include_directories(test-it8613-dxp480t PRIVATE
    ${CMAKE_CURRENT_SOURCE_DIR}/include
    ${CMAKE_CURRENT_SOURCE_DIR}
  )
  target_compile_options(test-it8613-dxp480t PRIVATE -Wall -Wextra -Wpedantic)
  add_test(NAME it8613-dxp480t COMMAND test-it8613-dxp480t)
  add_executable(test-it8613-dxp6800pro
    tests/test_it8613_dxp6800pro.c
    fan/it8613_dxp6800pro.c
  )
  target_include_directories(test-it8613-dxp6800pro PRIVATE
    ${CMAKE_CURRENT_SOURCE_DIR}/include
    ${CMAKE_CURRENT_SOURCE_DIR}
  )
  target_compile_options(test-it8613-dxp6800pro PRIVATE -Wall -Wextra -Wpedantic)
  add_test(NAME it8613-dxp6800pro COMMAND test-it8613-dxp6800pro)
  add_executable(test-it8613-dxp6800plus
    tests/test_it8613_dxp6800plus.c
    fan/it8613_dxp6800plus.c
  )
  target_include_directories(test-it8613-dxp6800plus PRIVATE
    ${CMAKE_CURRENT_SOURCE_DIR}/include
    ${CMAKE_CURRENT_SOURCE_DIR}
  )
  target_compile_options(test-it8613-dxp6800plus PRIVATE -Wall -Wextra -Wpedantic)
  add_test(NAME it8613-dxp6800plus COMMAND test-it8613-dxp6800plus)
  add_executable(test-it8613-dxp6800
    tests/test_it8613_dxp6800.c
    fan/it8613_dxp6800.c
  )
  target_include_directories(test-it8613-dxp6800 PRIVATE
    ${CMAKE_CURRENT_SOURCE_DIR}/include
    ${CMAKE_CURRENT_SOURCE_DIR}
  )
  target_compile_options(test-it8613-dxp6800 PRIVATE -Wall -Wextra -Wpedantic)
  add_test(NAME it8613-dxp6800 COMMAND test-it8613-dxp6800)
  add_executable(test-thermal-curve tests/test_thermal_curve.c)
  target_include_directories(test-thermal-curve PRIVATE
    ${CMAKE_CURRENT_SOURCE_DIR}/include
    ${CMAKE_CURRENT_SOURCE_DIR}
  )
  target_link_libraries(test-thermal-curve PRIVATE ugreenctl_hardware)
  target_compile_options(test-thermal-curve PRIVATE -Wall -Wextra -Wpedantic)
  add_test(NAME thermal-curve COMMAND test-thermal-curve)
endif()

if(BUILD_TESTING)
  foreach(test_name wake-profiles wake-cli rtc-runtime wol-interface)
    string(REPLACE "-" "_" test_source ${test_name})
    add_executable(test-${test_name} tests/test_${test_source}.c)
    target_link_libraries(test-${test_name} PRIVATE ugreenctl_hardware)
    target_compile_options(test-${test_name} PRIVATE -Wall -Wextra -Wpedantic -UNDEBUG)
    add_test(NAME ${test_name} COMMAND test-${test_name})
  endforeach()
endif()

if(BUILD_TESTING)
  add_executable(test-dxp6800-plugin tests/test_dxp6800_plugin.c models/dxp6800.c)
  target_include_directories(test-dxp6800-plugin PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}/include ${CMAKE_CURRENT_SOURCE_DIR})
  target_compile_options(test-dxp6800-plugin PRIVATE -Wall -Wextra -Wpedantic)
  add_test(NAME dxp6800-plugin COMMAND test-dxp6800-plugin)
endif()
