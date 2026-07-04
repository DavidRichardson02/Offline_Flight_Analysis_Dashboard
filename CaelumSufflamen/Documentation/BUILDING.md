# Building and Flashing

This repository targets `Teensy 4.1` and defines one canonical Arduino CLI build path for the current flattened Arduino sketch layout. The wrapper also still supports the older split `include/`, `src/`, and `utils/` layout if all three directories are present.

## Board and FQBN

- Board: `Teensy 4.1`
- Arduino CLI FQBN: `teensy:avr:teensy41`

## Required toolchain surfaces

- `arduino-cli`
- a Teensy board package that provides `teensy:avr:teensy41`
- sensor libraries matching enabled sensor backends. The current bench profile
  enables `LIS3DH_ENABLED=1` and `PMOD_CMPS2_ENABLED=1`, so it requires:
  - `Adafruit_LIS3DH.h`
  - `Adafruit_Sensor.h`
  - `Adafruit_BusIO` as an Adafruit library dependency
- legacy or alternate sensor profiles also require their matching libraries,
  such as `Adafruit_BMP5xx.h`, `BMI088.h`, and `LIS2DU12Sensor.h`.

## Canonical build command

```powershell
powershell -ExecutionPolicy Bypass -File .\tools\teensy41_arduino_cli.ps1 -ArduinoCli arduino-cli
```

The wrapper stages a normalized sketch under `.build/teensy41/staged_sketch/` by:

1. copying `CaelumSufflamen.ino` into the staged sketch root as `staged_sketch.ino`
2. copying root-level `*.h` and `*.hpp` files into the staged sketch root and `staged_sketch/src/`
3. copying root-level `.c`, `.cc`, and `.cpp` files into `staged_sketch/src/`
4. invoking `arduino-cli compile --fqbn teensy:avr:teensy41`

To regenerate only the staged sketch without invoking `arduino-cli`, run:

```powershell
powershell -ExecutionPolicy Bypass -File .\tools\teensy41_arduino_cli.ps1 -StageOnly
```

This keeps the source tree reviewable while still giving the repository one explicit build entrypoint.

## Canonical upload command

```powershell
powershell -ExecutionPolicy Bypass -File .\tools\teensy41_arduino_cli.ps1 -ArduinoCli arduino-cli -Upload -Port COM7
```

Replace `COM7` with the port reported for the connected Teensy by `arduino-cli board list`.

## Current Bench Sensor Profile

The default configuration is for the currently connected LIS3DH plus Pmod CMPS2
bench hardware. `STATUS` includes `lis_i2c_addr`, `cmps2_init`,
`cmps2_runtime`, and `cmps2_product_id` to make bring-up failures attributable.
`I2C_SCAN` should show a LIS3DH at `0x18` or `0x19` on `Wire` and a CMPS2 at
`0x30` on `Wire1`.

## Outputs

- Staged sketch: `.build/teensy41/staged_sketch/`
- Compiled binaries: `.build/teensy41/output/`

## Current limitations

- exact Teensy core version is still unpinned
- exact library versions are still unpinned
- the wrapper assumes `arduino-cli` can already resolve the Teensy platform and required libraries
- this is a canonical build and flash workflow, not a claim of cross-machine bit-for-bit reproducibility
