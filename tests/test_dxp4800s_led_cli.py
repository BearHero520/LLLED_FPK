#!/usr/bin/env python3
"""Compile the patched CLI with fake I2C; never access host hardware.

Pass --source to the upstream checkout after applying the bundled patches.
"""
import argparse
from pathlib import Path
import subprocess
import tempfile


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", required=True, type=Path)
    args = parser.parse_args()
    with tempfile.TemporaryDirectory(prefix="4800s-led-test-") as temporary:
        work = Path(temporary)
        # Redirect only filesystem discovery in the test copy. The production
        # binary retains real DMI and has no environment-based identity override.
        source = (args.source / "cli/ugreen_leds.cpp").read_text()
        source = source.replace('"/sys/class/i2c-dev/"', '"' + str(work / "bus") + '/"')
        source = source.replace('"/sys/class/dmi/id/product_name"', '"' + str(work / "product") + '"')
        (work / "controller.cpp").write_text(source)
        harness = r'''
#include <cassert>
#include <fstream>
#include <map>
#include "controller.cpp"
static std::string current;
static std::map<std::string, int> reads;
static bool valid = true;
static unsigned writes;
static std::vector<uint8_t> payload;
i2c_device_t::~i2c_device_t() {}
int i2c_device_t::start(const char *path, uint16_t address) {
    assert(address == 0x3a); current = path; return 0;
}
void i2c_device_t::close() {}
int i2c_device_t::read_word_data(uint8_t command, uint16_t &value) {
    assert(command == 0x5a);
    int count = ++reads[current];
    value = valid && current == "/dev/i2c-2" && count >= 2 ? 0xc5b2 : 0;
    return count == 1 ? -1 : 0;
}
std::vector<uint8_t> i2c_device_t::read_block_data(uint8_t, uint32_t) { return {}; }
int i2c_device_t::read_byte_data(uint8_t, uint8_t &value) { value = 1; return 0; }
int i2c_device_t::write_block_data(uint8_t command, std::vector<uint8_t> value) {
    assert(command == 5); ++writes; payload = value; return 0;
}
int i2c_device_t::write_byte_data(uint8_t, uint8_t) { assert(false); return -1; }
int main(int argc, char **argv) {
    assert(argc == 2);
    const std::filesystem::path root(argv[1]);
    auto product = [&](const char *name) { std::ofstream(root / "product") << name << '\n'; };
    product("DXP4800S");
    for (const auto &item : std::map<std::string, std::string>{
            {"i2c-0", "SMBus I801 adapter wrong"},
            {"i2c-1", "unrelated GPU bus"},
            {"i2c-2", "Synopsys DesignWare"}}) {
        auto path = root / "bus" / item.first;
        std::filesystem::create_directories(path);
        std::ofstream(path / "name") << item.second;
    }
    ugreen_leds_t leds;
    assert(leds.start() == 0);
    assert(reads["/dev/i2c-0"] == 3 && reads["/dev/i2c-2"] == 2);
    assert(reads.count("/dev/i2c-1") == 0 && writes == 0);
    assert(leds.set_onoff(static_cast<ugreen_leds_t::led_type_t>(5), 1) == 0);
    assert((payload == std::vector<uint8_t>{5, 0xa0, 1, 0, 0, 3, 1, 0, 0, 0, 0, 0xa5}));
    valid = false; reads.clear();
    assert(leds.start() != 0 && writes == 1);
    assert(reads["/dev/i2c-0"] == 3 && reads["/dev/i2c-2"] == 3);
    product("DXP4800S Engineering"); reads.clear();
    assert(leds.start() == 0 && reads.empty()); // unknown DMI retains prior path
    product("DX4600"); reads.clear();
    assert(leds.start() != 0 && reads["/dev/i2c-0"] == 3);
}
'''
        (work / "test.cpp").write_text(harness)
        subprocess.run(["g++", "-std=c++17", "-Wall", "-Wextra", "-I", str(args.source / "cli"),
                        str(work / "test.cpp"), "-o", str(work / "test")], check=True)
        subprocess.run([str(work / "test"), str(work)], check=True)
        print("DXP4800S LED discovery, retry, exact DMI and stock frame tests passed")


if __name__ == "__main__":
    main()
