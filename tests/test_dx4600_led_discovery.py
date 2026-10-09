#!/usr/bin/env python3
"""Exercise patched discovery against fake buses, without hardware access."""
import argparse
from pathlib import Path
import subprocess
import tempfile


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", required=True, type=Path)
    args = parser.parse_args()
    with tempfile.TemporaryDirectory(prefix="dx4600-discovery-") as temporary:
        work = Path(temporary)
        source = (args.source / "cli/ugreen_leds.cpp").read_text()
        source = source.replace('"/sys/class/i2c-dev/"', '"' + str(work / "bus") + '/"')
        source = source.replace('"/sys/class/dmi/id/product_name"', '"' + str(work / "product") + '"')
        (work / "controller.cpp").write_text(source)
        (work / "test.cpp").write_text(r'''
#include <cassert>
#include <fstream>
#include <map>
#include "controller.cpp"
static std::string current, valid_bus = "/dev/i2c-6", unavailable_bus;
static std::vector<std::string> opened;
static std::map<std::string, int> reads;
i2c_device_t::~i2c_device_t() {}
int i2c_device_t::start(const char *path, uint16_t address) {
    assert(address == 0x3a); current = path; opened.push_back(current);
    return current == unavailable_bus ? -1 : 0;
}
void i2c_device_t::close() {}
int i2c_device_t::read_word_data(uint8_t command, uint16_t &value) {
    assert(command == 0x5a); ++reads[current];
    value = current == valid_bus ? 0xc5b2 : 0; return 0;
}
std::vector<uint8_t> i2c_device_t::read_block_data(uint8_t, uint32_t) { return {}; }
int i2c_device_t::read_byte_data(uint8_t, uint8_t &) { return -1; }
int i2c_device_t::write_block_data(uint8_t, std::vector<uint8_t>) { assert(false); return -1; }
int i2c_device_t::write_byte_data(uint8_t, uint8_t) { assert(false); return -1; }
int main(int argc, char **argv) {
    assert(argc == 2); const std::filesystem::path root(argv[1]);
    auto product = [&](const char *name) { std::ofstream(root / "product") << name << '\n'; };
    for (int i = 0; i <= 7; ++i) {
        auto path = root / "bus" / ("i2c-" + std::to_string(i));
        std::filesystem::create_directories(path);
        std::ofstream(path / "name") << (i == 6 ? "SMBus I801 adapter" :
            i == 7 ? "i915 gmbus" : "Synopsys DesignWare I2C adapter");
    }
    ugreen_leds_t leds;
    for (auto name : {"DX4600", "DX4600+", "DX4600 Pro"}) {
        product(name); reads.clear(); opened.clear();
        assert(leds.start() == 0);
        assert(opened == std::vector<std::string>{"/dev/i2c-6"});
        assert(reads.size() == 1 && reads["/dev/i2c-6"] == 1);
    }
    // Bad signatures must not suppress the existing DesignWare fallback.
    valid_bus = "/dev/i2c-1"; reads.clear(); opened.clear();
    assert(leds.start() == 0 && opened.front() == "/dev/i2c-6");
    assert(reads["/dev/i2c-6"] == 3 && reads["/dev/i2c-0"] == 3 && reads["/dev/i2c-1"] == 1);
    // Failure to open I801 also falls back, without reading that unopened bus.
    unavailable_bus = "/dev/i2c-6"; reads.clear(); opened.clear();
    assert(leds.start() == 0 && reads.count("/dev/i2c-6") == 0);
    assert(reads["/dev/i2c-1"] == 1);
    unavailable_bus.clear(); valid_bus.clear(); reads.clear(); opened.clear();
    assert(leds.start() != 0 && reads.size() == 7);
    assert(reads.count("/dev/i2c-7") == 0);
    // DXP4800S retains its existing numeric order and validation.
    product("DXP4800S"); valid_bus = "/dev/i2c-1"; opened.clear();
    assert(leds.start() == 0 && opened.front() == "/dev/i2c-0");
}
''')
        subprocess.run(["g++", "-std=c++17", "-Wall", "-Wextra", "-I", str(args.source / "cli"),
                        str(work / "test.cpp"), "-o", str(work / "test")], check=True)
        subprocess.run([str(work / "test"), str(work)], check=True)
        print("DX4600 I801 priority, signature validation, fallback and model isolation passed")


if __name__ == "__main__":
    main()
