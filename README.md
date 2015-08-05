# SPIFlash 1.0.1

The SPIFlash class allows you to use a SPI Flash on the imp001 and imp002 with an interface similar to [hardware.spiflash](https://electricimp.com/docs/api/hardware/spiflash).

**To add this library to your project, add `#require "SPIFlash.class.nut:1.0.1"`` to the top of your device code.**

You can view the library’s source code on [GitHub](https://github.com/electricimp/spiflash/tree/v1.0.1).

## Class Usage

### Constructor: SPIFlash(*spi, cs_l, [blocks]*)

The class’ constructor takes two required parameters (a configured [hardware.spi](https://electricimp.com/docs/api/hardware/spi) object, and a [hardware.pin](https://electricimp.com/docs/api/hardware/pin1)) and an optional parameter (the I&sup2;C address of the sensor):


| Parameter     | Type         | Default | Description |
| ------------- | ------------ | ------- | ----------- |
| spi           | hardware.i2c | N/A     | A pre-configured spi bus |
| cs_l          | hardware.pin | N/A     | The chip select pin      |
| blocks        | number       | 64      | The nubmer of 64K blocks on the SPIFlash |

```squirrel
#require "SPIFlash.class.nut:1.0.1"

spi <- hardware.spi257;
spi.configure(CLOCK_IDLE_LOW | MSB_FIRST, 30000);

cs <- hardware.pin8;

spiFlash <- SPIFlash(spi, cs);
```

## Class Methods

The SPIFlash class conforms to the [hardware.spiflash] API, and all methods available to the hardware.spiflash object are available to instantiated SPIFlash objects. For more in depth usage and examples, see the [hardware.spiflash documentation](https://electricimp.com/docs/api/hardware/spiflash).

### configure(*[dataRate_kHz]*)

The configure method will autoconfigure the SPI bus passed into the constructor, and return the set datarate.

```squirrel
#require "SPIFlash.class.nut:1.0.1"

spiFlash <- SPIFlash(hardware.spi257, hardware.pin8);
spiFlash.configure(30000);
```

## chipid()

Returns the identity code of the SPI flash chip.

See [hardware.spiflash.chipid()](https://electricimp.com/docs/api/hardware/spiflash/chipid) for more information.

```squirrel
spiFlash.enable();
server.log(spiFlash.chipid());
```

## disable()

Disables the SPI flash for reading and writing.

See [hardware.spiflash.disable()](https://electricimp.com/docs/api/hardware/spiflash/disable) for more information.

```squirrel
spiFlash.disable();
```

## enable()

Enables the SPI flash for reading and writing.

See [hardware.spiflash.enable()](https://electricimp.com/docs/api/hardware/spiflash/enable) for more information.

```squirrel
spiFlash.enable();
```

## erasesector(*sectorAddress*)

Erases a 4KB sector of the SPI flash.

See [hardware.spiflash.erasesector()](https://electricimp.com/docs/api/hardware/spiflash/erasesector) for more information.

```squirrel
// Erase the first 3 sectors
spiFlash.erasesector(0x0000);
spiFlash.erasesector(0x1000);
spiFlash.erasesector(0x2000);
```


## read(*address, numberOfBytes*)

Copies data from the SPI flash and returns it as a series of bytes.

See [hardware.spiflash.read()](https://electricimp.com/docs/api/hardware/spiflash/read) for more information.

```squirrel
spiFlash.enable();
// Read 36 bytes from the beginning of the third sector
local buffer = spiFlash.read(0x2000, 36);
spiFlash.disable();
```

## readintoblob(*address, targetBlob, numberOfBytes*)

Copies data from the SPI flash storage into a pre-existing blob.

See [hardware.spiflash.readintoblob()](https://electricimp.com/docs/api/hardware/spiflash/readintoblob) for more information.

```squirrel
buffer <- blob(1024);

spiFlash.enable();
spiFlash.readintoblob(0x1000, buffer, 128);
spiFlash.readintoblob(0x2000, buffer, 256);
spiFlash.disable();
```

## size()

Returns the total number of bytes in the SPI flash that are available to Squirrel.

See [hardware.spiflash.size()](https://electricimp.com/docs/api/hardware/spiflash/size) for more information.

```squirrel
spiFlash.enable();
server.log(spiFlash.size() + " Bytes");
```

## write(*address, dataSource, writeFlags, startIndex, endIndex*)

Writes a full or partial blob into the SPI flash.

See [hardware.spiflash.write()](https://electricimp.com/docs/api/hardware/spiflash/write) for more information.

# License

The SPIFlash class is licensed under [MIT License](https://github.com/electricimp/spiflash/tree/master/LICENSE).
