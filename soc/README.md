# Ava BASIC SoC

`python -m avasoc build -p` will build for iCEBreaker and program.

`python -m avasoc flash` will flash `avasoc.bin` built in `/core` to the iCEBreaker's SPI flash.

`python -m avasoc cxxrtl` will build and run the CXXRTL/Zig simulation.

`python -m avasoc` for usage.


## VexRiscv build

You can find the branch we build our VexRiscv core from at [`charlottia/VexRiscv`].

The CXXRTL simulation exposes its UART on a Unix domain socket, which the [Amateur Development Client] can connect to.

[`charlottia/VexRiscv`]: https://github.com/charlottia/VexRiscv
[Amateur Development Client]: ../adc
