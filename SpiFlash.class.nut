/*

Designed to be fully compatible with hardware.spiflash https://electricimp.com/docs/api/hardware/spiflash/

Notes:
- There doesn't seem to be a non-destructive method for measuring the size()

*/


// -----------------------------------------------------------------------------
class SPIFlash {

    _spi = null;
    _cs_l = null;
    _blocks = null;

    _cs_l_w = null;
    _spi_w = null;
    _spi_wr = null;
    _millis = null;

    _enabled = false;

    _SPIFLASH_PREVERIFY = 2;
    _SPIFLASH_POSTVERIFY = 1;

    _version = [0, 1, 0];

    // -------------------------------------------------------------------------
    // constructor takes in pre-configured spi interface object and chip select GPIO
    // the third parameter lets you specify the number of 64k blocks
    constructor(spi, cs_l, blocks = 64) {

        const WREN     = 0x06; // write enable
        const WRDI     = 0x04; // write disable
        const RDID     = 0x9F; // read identification
        const RDSR     = 0x05; // read status register
        const READ     = 0x03; // read data
        const RES      = 0xAB; // read electronic ID
        const REMS     = 0x90; // read electronic mfg & device ID
        const SE       = 0x20; // sector erase (Any 4kbyte sector set to 0xff)
        const BE       = 0x52; // block erase (Any 64kbyte sector set to 0xff)
        const CE       = 0x60; // chip erase (full device set to 0xff)
        const PP       = 0x02; // page program
        const DP       = 0xB9; // deep power down
        const RDP      = 0xAB; // release from deep power down

        const BLOCK_SIZE = 65536;
        const SECTOR_SIZE = 4096;

        const COMMAND_TIMEOUT = 10000; // milliseconds

        const SPI_NOT_ENABLED = "Not enabled";
        const SPI_SECTOR_BOUNDARY = "This request must be aligned with a sector (4kb)"
        const SPI_WRENABLE_FAILED = "Write failed";
        const SPI_WAITFORSTATUS_TIMEOUT = "Timeout waiting for status change";

        _spi = spi;
        _cs_l = cs_l;
        _blocks = blocks;
        _enabled = true;

        // We can safely configure the GPIO lines
        _cs_l.configure(DIGITAL_OUT, 1);

        // For speed, we cache a few functions
        _cs_l_w = _cs_l.write.bindenv(_cs_l);
        _spi_w = _spi.write.bindenv(spi);
        _spi_wr = _spi.writeread.bindenv(spi);
        _millis = hardware.millis.bindenv(hardware);

        // Make sure we have SPIFLASH_PREVERIFY and SPIFLASH_POSTVERIFY defined and accurate
        try {
            _SPIFLASH_PREVERIFY = SPIFLASH_PREVERIFY;
            _SPIFLASH_POSTVERIFY = SPIFLASH_POSTVERIFY;
        } catch (e) { }
    }

    // -------------------------------------------------------------------------
    // spiflash.configure() - [optional] configures the SPI lines
    function configure(speed = 15000) {
        return _spi.configure(CLOCK_IDLE_LOW | MSB_FIRST, speed);
    }

    // -------------------------------------------------------------------------
    // spiflash.size() â€“ Returns the total number of bytes in the SPI flash that are available to Squirrel.
    function size() {
        return _blocks * BLOCK_SIZE;
    }

    // -------------------------------------------------------------------------
    // spiflash.disable() â€“ Disables the SPI flash for reading and writing.
    function disable() {
        if (!_enabled) throw SPI_NOT_ENABLED;
        _enabled = false;

        _cs_l_w(0);
        _spi_w(DP.tochar());
        _cs_l_w(1);
    }

    // -------------------------------------------------------------------------
    // spiflash.enable() â€“ Enables the SPI flash for reading and writing.
    function enable() {
        _enabled = true;

        _cs_l_w(0);
        _spi_w(RDP.tochar());
        _cs_l_w(1);
    }

    // -------------------------------------------------------------------------
    // spiflash.chipid() â€“ Returns the identity of the SPI flash chip.
    function chipid() {

        if (!_enabled) throw SPI_NOT_ENABLED;

        _cs_l_w(0);
        _spi_w(RDID.tochar());
        local data = _spi.readblob(3);
        _cs_l_w(1);

        return (data[0] << 16) | (data[1] << 8) | (data[2]);

    }

    // -------------------------------------------------------------------------
    // spiflash.erasesector(integer) â€“ Erases a 4KB sector of the SPI flash.
    function erasesector(sector) {

        if (!_enabled) throw SPI_NOT_ENABLED;
        if ((sector % SECTOR_SIZE) != 0) throw SPI_SECTOR_BOUNDARY;

        _wrenable();
        _cs_l_w(0);
        _spi_w(format("%c%c%c%c", SE, (sector >> 16) & 0xFF, (sector >> 8) & 0xFF, sector & 0xFF));
        _cs_l_w(1);

        _waitForStatus();

    }

    // -------------------------------------------------------------------------
    // spiflash.read(integer, integer) â€“ Copies data from the SPI flash and returns it as a series of bytes.
    function read(addr, bytes) {

        if (!_enabled) throw SPI_NOT_ENABLED;

        _cs_l_w(0);
        _spi_w(format("%c%c%c%c", READ, (addr >> 16) & 0xFF, (addr >> 8) & 0xFF, addr & 0xFF));
        local readBlob = _spi.readblob(bytes);
        _cs_l_w(1);

        return readBlob;

    }

    // -------------------------------------------------------------------------
    // spiflash.readintoblob(integer, blob, integer) â€“ Copies data from the SPI flash storage into a pre-existing blob.
    function readintoblob(addr, data, bytes) {
        // This is a silly hack but I can't do much about it.
        data.writeblob(read(addr, bytes));
    }

    // -------------------------------------------------------------------------
    // spiflash.write(integer, blob, const, integer, integer) â€“ Writes a full or partial blob into the SPI flash.
    function write(address, data, verification = 0, data_start = null, data_end = null) {

        if (!_enabled) throw SPI_NOT_ENABLED;

        local addr = address, start = data_start, end = data_end;

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
        if (verification & _SPIFLASH_PREVERIFY) {
            data.seek(data_start);
            if (!_preverify(data, address, data_end-data_start)) {
                return _SPIFLASH_PREVERIFY;
            }
        }

        // Get ready
        local data_r = data.readblob.bindenv(data);
        data.seek(start);

        // Realign to the chunk boundary
        local left_in_chunk = 256 - (addr % 256);
        if (left_in_chunk > 0) {
            // server.log(format("Realign: addr=%d, start=%d, left=%d", addr, start, left_in_chunk))
            _write(addr, data_r(left_in_chunk));
            addr += left_in_chunk;
            start += left_in_chunk;
        }

        // Write the remaining data in 256 byte chunks
        local len = end - start;
        while (len > 0) {
            left_in_chunk = len > 256 ? 256 : len;
            // server.log(format("Write: addr=%d, start=%d, left=%d", addr, start, left_in_chunk))
            _write(addr, data_r(left_in_chunk));
            addr += left_in_chunk;
            start += left_in_chunk;
            len -= left_in_chunk;
        }

        // Post verify if requested
        if (verification & _SPIFLASH_POSTVERIFY) {
            data.seek(data_start);
            if (!_postverify(data, address, data_end-data_start)) {
                return _SPIFLASH_POSTVERIFY;
            }
        }

        return 0;
    }

    // -------------------------------------------------------------------------
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

    // -------------------------------------------------------------------------
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

    // -------------------------------------------------------------------------
    function _write(addr, data) {

        _wrenable();

        _cs_l_w(0);
        _spi_w(format("%c%c%c%c", PP, (addr >> 16) & 0xFF, (addr >> 8) & 0xFF, addr & 0xFF));
        _spi_w(data);
        _cs_l_w(1);

        _waitForStatus();
    }

    // -------------------------------------------------------------------------
    function _wrenable(timeout = COMMAND_TIMEOUT) {

        local now = _millis();
        do {
            _cs_l_w(0);
            _spi_w(WREN.tochar());
            _cs_l_w(1);

            if ((_getStatus() & 0x03) == 0x02) return true;
        } while (_millis() - now < timeout);

        throw SPI_WRENABLE_FAILED;

    }

    // -------------------------------------------------------------------------
    function _getStatus() {

        _cs_l_w(0);
        local status = _spi_wr(format("%c%c", RDSR, 0));
        _cs_l_w(1);

        return status[1];
    }

    // -------------------------------------------------------------------------
    function _waitForStatus(mask = 0x01, value = 0x00, timeout = COMMAND_TIMEOUT) {

        local now = _millis();
        do {
            if ((_getStatus() & mask) == value) {
                return;
            }
        } while (_millis() - now < timeout);

        throw SPI_WAITFORSTATUS_TIMEOUT;
    }

}
