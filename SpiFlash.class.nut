// Copyright (c) 2015 Electric Imp
// This file is licensed under the MIT License
// http://opensource.org/licenses/MIT

// This class is designed to be fully compatible with hardware.spiflash

// Declare fully namespaced constants (ACCOUNT_CLASS_CONST)
// We used consts rather than statics for hardware optimization

const ELECTRICIMP_SPIFLASH_WREN     = "\x06";       // write enable
const ELECTRICIMP_SPIFLASH_WRDI     = 0x04;         // write disable
const ELECTRICIMP_SPIFLASH_RDID     = "\x9F";       // read identification
const ELECTRICIMP_SPIFLASH_RDSR     = "\x05\x00";   // read status register
const ELECTRICIMP_SPIFLASH_READ     = "\x03%c%c%c"; // read data
const ELECTRICIMP_SPIFLASH_RES      = 0xAB;         // read electronic ID
const ELECTRICIMP_SPIFLASH_REMS     = 0x90;         // read electronic mfg & device ID
const ELECTRICIMP_SPIFLASH_SE       = "\x20%c%c%c"; // sector erase (Any 4kbyte sector set to 0xff)
const ELECTRICIMP_SPIFLASH_BE       = 0x52;         // block erase (Any 64kbyte sector set to 0xff)
const ELECTRICIMP_SPIFLASH_CE       = 0x60;         // chip erase (full device set to 0xff)
const ELECTRICIMP_SPIFLASH_PP       = 0x02;         // page program
const ELECTRICIMP_SPIFLASH_DP       = "\xB9";       // deep power down
const ELECTRICIMP_SPIFLASH_RDP      = "\xAB";       // release from deep power down

const ELECTRICIMP_SPIFLASH_BLOCK_SIZE = 65536;
const ELECTRICIMP_SPIFLASH_SECTOR_SIZE = 4096;

const ELECTRICIMP_SPIFLASH_COMMAND_TIMEOUT = 10000; // milliseconds

class SPIFlash {

    // Library version
    _version = [1, 0, 0];

    // class members
    _spi = null;
    _cs_l = null;
    _blocks = null;
    _enabled = null;

    // aliased functions to speed things up
    _cs_l_w = null;
    _spi_w = null;
    _spi_wr = null;
    _millis = null;

    // Errors:
    static SPI_NOT_ENABLED = "Not enabled";
    static SPI_SECTOR_BOUNDARY = "This request must be aligned with a sector (4kb)"
    static SPI_ELECTRICIMP_SPIFLASH_WRENABLE_FAILED = "Write failed";
    static SPI_WAITFORSTATUS_TIMEOUT = "Timeout waiting for status change";

    // constructor takes in pre-configured spi interface object and chip select GPIO
    // the third parameter lets you specify the number of 64k blocks
    constructor(spi, cs_l, blocks = 64) {
        _spi = spi;
        _cs_l = cs_l;
        _blocks = blocks;
        _enabled = false;

        // For speed, we cache a few functions
        _cs_l_w = _cs_l.write.bindenv(_cs_l);
        _spi_w = _spi.write.bindenv(spi);
        _spi_wr = _spi.writeread.bindenv(spi);
        _millis = hardware.millis.bindenv(hardware);

        // We can safely configure the GPIO lines
        _cs_l.configure(DIGITAL_OUT, 1);
    }

    // spiflash.configure() - [optional] configures the SPI lines
    function configure(speed = 15000) {
        return _spi.configure(CLOCK_IDLE_LOW | MSB_FIRST, speed);
    }

    // spiflash.size() - Returns the total number of bytes in the SPI flash that are available to Squirrel.
    function size() {
        // Throw error if disabled
        if (!_enabled) throw SPI_NOT_ENABLED;

        return _blocks * ELECTRICIMP_SPIFLASH_BLOCK_SIZE;
    }

    // spiflash.disable() - Disables the SPI flash for reading and writing.
    function disable() {
        // if we're already disabled, return
        if(!_enabled) return;

        _enabled = false;

        _cs_l_w(0);
        _spi_w(ELECTRICIMP_SPIFLASH_DP);
        _cs_l_w(1);
    }

    // spiflash.enable() - Enables the SPI flash for reading and writing.
    function enable() {
        // If we're already enabled, return
        if (_enabled) return;

        _enabled = true;

        _cs_l_w(0);
        _spi_w(ELECTRICIMP_SPIFLASH_RDP);
        _cs_l_w(1);
    }

    // spiflash.chipid() - Returns the identity of the SPI flash chip.
    function chipid() {
        // Throw error if disabled
        if (!_enabled) throw SPI_NOT_ENABLED;

        _cs_l_w(0);
        _spi_w(ELECTRICIMP_SPIFLASH_RDID);
        local data = _spi.readblob(3);
        _cs_l_w(1);

        return (data[0] << 16) | (data[1] << 8) | (data[2]);
    }

    // spiflash.erasesector(integer) - Erases a 4KB sector of the SPI flash.
    function erasesector(sector) {
        // Throw error if disabled
        if (!_enabled) throw SPI_NOT_ENABLED;

        if ((sector % ELECTRICIMP_SPIFLASH_SECTOR_SIZE) != 0) throw SPI_SECTOR_BOUNDARY;

        _cs_l_w(0);
        _wrenable();
        _spi_w(format(ELECTRICIMP_SPIFLASH_SE, (sector >> 16) & 0xFF, (sector >> 8) & 0xFF, sector & 0xFF));
        _waitForStatus();
        _cs_l_w(1);
    }

    // spiflash.read(integer, integer) - Copies data from the SPI flash and returns it as a series of bytes.
    function read(addr, bytes) {
        // Throw error if disabled
        if (!_enabled) throw SPI_NOT_ENABLED;

        _cs_l_w(0);
        _spi_w(format(ELECTRICIMP_SPIFLASH_READ, (addr >> 16) & 0xFF, (addr >> 8) & 0xFF, addr & 0xFF));
        local readBlob = _spi.readblob(bytes);
        _cs_l_w(1);

        return readBlob;
    }

    // spiflash.readintoblob(integer, blob, integer) - Copies data from the SPI flash storage into a pre-existing blob.
    function readintoblob(addr, data, bytes) {
        data.writeblob(read(addr, bytes));
    }

    // spiflash.write(integer, blob, const, integer, integer) - Writes a full or partial blob into the SPI flash.
    function write(address, data, verification = 0, data_start = null, data_end = null) {
        // Throw error if disabled
        if (!_enabled) throw SPI_NOT_ENABLED;

        local addr = address;
        local start = data_start
        local end = data_end;

        if (typeof data == "string") {
            // Convert string to blob
            if (start == null) start = 0;
            if (end == null) end = data.len();
            local newdata = blob();
            newdata.writestring(data.slice(start, end));

            // Replace all the parameters
            data = newdata;
            start = end = null;
        }

        // Fix up the parameters
        if (start == null) start = data_start = 0;
        if (end == null) end = data_end = data.len();

        // Preverify if requested
        if (verification & SPIFLASH_PREVERIFY) {
            data.seek(data_start);
            if (!_preverify(data, address, data_end-data_start)) {
                return SPIFLASH_PREVERIFY;
            }
        }

        // Get ready
        local data_r = data.readblob.bindenv(data);
        data.seek(start);

        // Realign to the chunk boundary
        local left_in_chunk = 256 - (addr % 256);
        if (left_in_chunk > 0) {
            _write(addr, data_r(left_in_chunk));
            addr += left_in_chunk;
            start += left_in_chunk;
        }

        // Write the remaining data in 256 byte chunks
        local len = end - start;
        while (len > 0) {
            left_in_chunk = len > 256 ? 256 : len;
            _write(addr, data_r(left_in_chunk));
            addr += left_in_chunk;
            start += left_in_chunk;
            len -= left_in_chunk;
        }

        // Post verify if requested
        if (verification & SPIFLASH_POSTVERIFY) {
            data.seek(data_start);
            if (!_postverify(data, address, data_end-data_start)) {
                return SPIFLASH_POSTVERIFY;
            }
        }

        return 0;
    }


    //-------------------- PRIVATE METHODS --------------------//
    function _preverify(data, addr, len) {
        // Verify in chunks no bigger than 256 bytes
        if (len <= 256) {
            local olddata = read(addr, len);
            if (olddata.len() != len) return false;
            for (local i = 0; i < len; i++) {
                local pre = olddata.readn('b');
                local it = data.readn('b');
                local post = pre & it;
                if (post != it) return false;
            }
        } else {
            do {
                local result = _preverify(data, addr, len >= 256 ? 256 : len);
                if (result == false) return false;
                len -= 256;
                addr += 256;
            } while (len > 0);
        }
        return true;
    }

    function _postverify(data, addr, len) {
        // Verify in chunks no bigger than 256 bytes
        if (len <= 256) {
            local newdata = read(addr, len)
            if (newdata.len() != len) return false;
            for (local i = 0; i < len; i++) {
                if (newdata.readn('b') != data.readn('b')) return false;
            }
        } else {
            do {
                local result = _postverify(data, addr, len >= 256 ? 256 : len);
                if (result == false) return false;
                len -= 256;
                addr += 256;
            } while (len > 0);
        }
        return true;
    }

    function _write(addr, data) {
        _cs_l_w(0);

        _wrenable();
        _spi_w(format("%c%c%c%c", ELECTRICIMP_SPIFLASH_PP, (addr >> 16) & 0xFF, (addr >> 8) & 0xFF, addr & 0xFF));
        _spi_w(data);
        _waitForStatus();

        _cs_l_w(1);
    }

    function _wrenable(timeout = ELECTRICIMP_SPIFLASH_COMMAND_TIMEOUT) {
        local now = _millis();

        do {
            _spi_w(ELECTRICIMP_SPIFLASH_WREN);

            if ((_spi_wr(ELECTRICIMP_SPIFLASH_RDSR)[1] & 0x03) == 0x02) {
                return true;
            }
        } while (_millis() - now < timeout);

        throw SPI_ELECTRICIMP_SPIFLASH_WRENABLE_FAILED;
    }

    function _waitForStatus(mask = 0x01, value = 0x00, timeout = ELECTRICIMP_SPIFLASH_COMMAND_TIMEOUT) {
        local now = _millis();
        do {
            if ((_spi_wr(ELECTRICIMP_SPIFLASH_RDSR)[1] & mask) == value) {
                return;
            }
        } while (_millis() - now < timeout);

        throw SPI_WAITFORSTATUS_TIMEOUT;
    }

}
