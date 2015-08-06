// Copyright (c) 2015 Electric Imp
// This file is licensed under the MIT License
// http://opensource.org/licenses/MIT

// This class is designed to be fully compatible with hardware.spiflash

// Declare fully namespaced constants (ACCOUNT_CLASS_CONST)
// We used consts rather than statics for hardware optimization
const SPIFLASH_WREN     = "\x06";       // write enable
const SPIFLASH_RDID     = "\x9F";       // read identification
const SPIFLASH_RDSR     = "\x05\x00";   // read status register
const SPIFLASH_READ     = "\x03%c%c%c"; // read data
const SPIFLASH_SE       = "\x20%c%c%c"; // sector erase (Any 4kbyte sector set to 0xff)
const SPIFLASH_PP       = "\x02%c%c%c"; // page program
const SPIFLASH_DP       = "\xB9";       // deep power down
const SPIFLASH_RDP      = "\xAB";       // release from deep power down

const SPIFLASH_WRDI     = 0x04;         // write disable - unused
const SPIFLASH_BE       = 0x52;         // block erase (Any 64kbyte sector set to 0xff) - unused
const SPIFLASH_CE       = 0x60;         // chip erase (full device set to 0xff) - unused
const SPIFLASH_RES      = 0xAB;         // read electronic ID - unused
const SPIFLASH_REMS     = 0x90;         // read electronic mfg & device ID - unused

const SPIFLASH_BLOCK_SIZE = 65536;
const SPIFLASH_SECTOR_SIZE = 4096;

const SPIFLASH_COMMAND_TIMEOUT = 10000; // milliseconds (should be 10 seconds)

class SPIFlash {
    // Library version
    _version = [1, 0, 1];

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
    static SPI_WRENABLE_FAILED = "Write failed";
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

        return _blocks * SPIFLASH_BLOCK_SIZE;
    }

    // spiflash.disable() - Disables the SPI flash for reading and writing.
    function disable() {
        // if we're already disabled, return
        if(!_enabled) return;

        _enabled = false;

        _cs_l_w(0);
        _spi_w(SPIFLASH_DP);
        _cs_l_w(1);
    }

    // spiflash.enable() - Enables the SPI flash for reading and writing.
    function enable() {
        // If we're already enabled, return
        if (_enabled) return;

        _enabled = true;

        _cs_l_w(0);
        _spi_w(SPIFLASH_RDP);
        _cs_l_w(1);

        // if status register is already set, don't need to call _waitForStatus
        _cs_l_w(0); local status = _spi_wr(SPIFLASH_RDSR)[1]; _cs_l_w(1);
        if ((status & 0x01) == 0x00) return;

        _waitForStatus();
    }

    // spiflash.chipid() - Returns the identity of the SPI flash chip.
    function chipid() {
        // Throw error if disabled
        if (!_enabled) throw SPI_NOT_ENABLED;

        _cs_l_w(0);
        _spi_w(SPIFLASH_RDID);
        local data = _spi.readblob(3);
        _cs_l_w(1);

        return (data[0] << 16) | (data[1] << 8) | (data[2]);
    }

    // spiflash.erasesector(integer) - Erases a 4KB sector of the SPI flash.
    function erasesector(sector) {
        // Throw error if disabled
        if (!_enabled) throw SPI_NOT_ENABLED;
        if ((sector % SPIFLASH_SECTOR_SIZE) != 0) throw SPI_SECTOR_BOUNDARY;

        _wrenable();

        _cs_l_w(0);
        _spi_w(format(SPIFLASH_SE, (sector >> 16) & 0xFF, (sector >> 8) & 0xFF, sector & 0xFF));
        _cs_l_w(1);

        _waitForStatus();
    }

    // spiflash.read(integer, integer) - Copies data from the SPI flash and returns it as a series of bytes.
    function read(addr, bytes) {
        // Throw error if disabled
        if (!_enabled) throw SPI_NOT_ENABLED;

        _cs_l_w(0);
        _spi_w(format(SPIFLASH_READ, (addr >> 16) & 0xFF, (addr >> 8) & 0xFF, addr & 0xFF));
        local readBlob = _spi.readblob(bytes);
        _cs_l_w(1);

        return readBlob;
    }

    // spiflash.readintoblob(integer, blob, integer) - Copies data from the SPI flash storage into a pre-existing blob.
    function readintoblob(addr, data, bytes) {
        data.writeblob(read(addr, bytes));
    }

    // spiflash.write(integer, blob, const, integer, integer) - Writes a full or partial blob into the SPI flash.
    function write(address, data, verification = 0, data_start = null, data_end = null, chunk = 256) {
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
        }

        // Fix up the parameters
        if (start == null) start = data_start = 0;
        if (end == null) end = data_end = data.len();

        // Preverify if requested
        if (verification & SPIFLASH_PREVERIFY) {
            data.seek(data_start);
            // if (!_preverify(data, address, data_end-data_start)) {
            if (!_preverify(data, address, data_start, data_end-data_start)) {
                return SPIFLASH_PREVERIFY;
            }
        }

        // Get ready
        local data_r = data.readblob.bindenv(data);
        data.seek(start);

        // Realign to the chunk boundary
        local left_in_chunk = chunk - (addr % chunk);
        if (left_in_chunk > 0) {
            _write(addr, data_r(left_in_chunk));
            addr += left_in_chunk;
            start += left_in_chunk;
        }

        // Write the remaining data in 256 byte chunks
        local len = end - start;
        while (len > 0) {
            left_in_chunk = len > chunk ? chunk : len;
            _write(addr, data_r(left_in_chunk));
            addr += left_in_chunk;
            start += left_in_chunk;
            len -= left_in_chunk;
        }

        // Post verify if requested
        if (verification & SPIFLASH_POSTVERIFY) {
            data.seek(data_start);
            if (!_postverify(data, address, data_start, data_end-data_start)) {
                return SPIFLASH_POSTVERIFY;
            }
        }

        return 0;
    }


    //-------------------- PRIVATE METHODS --------------------//
    function _preverify(data, spiAddr, blobAddr, len, chunk = 512) {
        // If we're processing a chunk
        if (len <= chunk) {
            local olddata = read(spiAddr, len).tostring();
            if (olddata.len() != len) return false;

            data.seek(blobAddr);
            local newdata = data.readstring(len);

            // Check to make sure we're not setting any 0's to 1's
            for(local i = 0; i < len; i++) {
                if ((olddata[i] & newdata[i]) != newdata[i]) return false;
            }

            return true;
        }

        // If we need to chunk the data
        do {
            local result = _preverify(data, spiAddr, blobAddr, len >= chunk ? chunk : len, chunk);
            if (result == false) return false;

            len -= chunk;
            spiAddr += chunk;
            blobAddr += chunk;
        } while (len > 0);

        return true;
    }

    function _postverify(data, spiAddr, blobAddr, len, chunk = 512) {
        // If we're processing a chunk
        if (len <= chunk) {
            local newdata = read(spiAddr, len).tostring();
            if (newdata.len() != len) return false;

            data.seek(blobAddr);
            local olddata = data.readstring(len);

            if (olddata != newdata) return false;

            // If we have more than 4 bytes to read, read as long int
            // otherwise read as a single byte
            return true;
        }

        // If we need to chunk the data
        do {
            local result = _postverify(data, spiAddr, blobAddr, len >= chunk ? chunk : len, chunk);
            if (result == false) return false;

            len -= chunk;
            spiAddr += chunk;
            blobAddr += chunk;
        } while (len > 0);

        return true;
    }

    function _write(addr, data) {
        _wrenable();

        _cs_l_w(0);
        _spi_w(format(SPIFLASH_PP, (addr >> 16) & 0xFF, (addr >> 8) & 0xFF, addr & 0xFF));
        _spi_w(data);
        _cs_l_w(1);

        // if status register is already set, don't need to call _waitForStatus
        _cs_l_w(0); local status = _spi_wr(SPIFLASH_RDSR)[1]; _cs_l_w(1);
        if ((status & 0x01) == 0x00) return;

        _waitForStatus();
    }

    // -------------------------------------------------------------------------
    function _wrenable(timeout = SPIFLASH_COMMAND_TIMEOUT) {
        local end = _millis()+timeout;

        do {
            _cs_l_w(0);
            _spi_w(SPIFLASH_WREN);
            _cs_l_w(1);

            _cs_l_w(0);
            local status = _spi_wr(SPIFLASH_RDSR)[1];
            _cs_l_w(1);

            if ((status & 0x03) == 0x02) return true;
        } while (_millis() < end);

        throw SPI_WRENABLE_FAILED;
    }

    function _waitForStatus(mask = 0x01, value = 0x00, timeout = SPIFLASH_COMMAND_TIMEOUT) {
        local end = _millis()+timeout;
        do {
            _cs_l_w(0);
            local status = _spi_wr(SPIFLASH_RDSR)[1];
            _cs_l_w(1);

            if ((status & mask) == value) return;
        } while (_millis() < end);

        throw SPI_WAITFORSTATUS_TIMEOUT;
    }
}
