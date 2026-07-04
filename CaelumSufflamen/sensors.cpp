#include "sensors.h"

#include <SPI.h>
#include <Wire.h>
#include <math.h>

#include "config.h"

#if BMP5XX_ENABLED
#include <Adafruit_Sensor.h>
#include "Adafruit_BMP5xx.h"
#endif

#if BMI088_ENABLED
#include "BMI088.h"
#endif

#if LIS2DU12_ENABLED
#include <LIS2DU12Sensor.h>
#endif

#if LIS3DH_ENABLED
#include <Adafruit_LIS3DH.h>
#include <Adafruit_Sensor.h>
#endif

#include "math_utils.h"

/*
sensors.cpp
===============================================================================
PURPOSE
  Own physical sensor objects and publish validity-qualified snapshots.

DETERMINISM
  Runtime poll functions make at most one acquisition attempt per call. No
  runtime poll function waits for readiness. The only bounded waits are boot or
  operator-commanded diagnostics/calibrations.
===============================================================================
*/

#if BMP5XX_ENABLED
static Adafruit_BMP5xx bmp;
#endif

#if BMI088_ENABLED
static Bmi088Accel accel(Wire, 0x18);
static Bmi088Gyro gyro(Wire, 0x68);
#endif

#if LIS2DU12_ENABLED
static LIS2DU12Sensor lis(&Wire);
#endif

#if LIS3DH_ENABLED
static Adafruit_LIS3DH lis3dh(&Wire);
static uint8_t lis3dh_active_i2c_addr = 0U;
#endif

#if PMOD_CMPS2_ENABLED
static const uint8_t CMPS2_REG_XOUT_L = 0x00;
static const uint8_t CMPS2_REG_STATUS = 0x06;
static const uint8_t CMPS2_REG_CONTROL0 = 0x07;
static const uint8_t CMPS2_REG_PRODUCT_ID = 0x20;

static const uint8_t CMPS2_STATUS_MEAS_DONE = 0x01;
static const uint8_t CMPS2_CONTROL0_TAKE_MEASUREMENT = 0x01;
static const uint8_t CMPS2_CONTROL0_SET_SENSOR = 0x20;
static const uint8_t CMPS2_EXPECTED_PRODUCT_ID = 0x06;

static bool cmps2_measurement_pending = false;
static uint32_t cmps2_measurement_started_ms = 0;
static uint32_t cmps2_ready_after_ms = 0;
static uint8_t cmps2_product_id = 0;
static uint8_t cmps2_init_status = 1U;
static uint8_t cmps2_runtime_status = 1U;
#endif

#if PMOD_ACL2_ENABLED || PMOD_ACL_ENABLED
static void pmod_acl_spi_select(void) {
  digitalWrite(PIN_PMOD_ACL_SPI_CS, LOW);
}

static void pmod_acl_spi_deselect(void) {
  digitalWrite(PIN_PMOD_ACL_SPI_CS, HIGH);
}

static void pmod_acl_spi_begin(void) {
  pinMode(PIN_PMOD_ACL_SPI_CS, OUTPUT);
  pmod_acl_spi_deselect();
  SPI.begin();
}
#endif

#if PMOD_ACL2_ENABLED
static SPISettings acl2_spi_settings(void) {
  return SPISettings(PMOD_ACL_SPI_HZ, MSBFIRST, SPI_MODE0);
}

static uint8_t acl2_read_reg(uint8_t reg) {
  SPI.beginTransaction(acl2_spi_settings());
  pmod_acl_spi_select();
  SPI.transfer(0x0B);
  SPI.transfer(reg);
  const uint8_t value = SPI.transfer(0x00);
  pmod_acl_spi_deselect();
  SPI.endTransaction();

  return value;
}

static void acl2_read_regs(uint8_t reg, uint8_t *dst, uint8_t len) {
  if (!dst || len == 0U) {
    return;
  }

  SPI.beginTransaction(acl2_spi_settings());
  pmod_acl_spi_select();
  SPI.transfer(0x0B);
  SPI.transfer(reg);

  for (uint8_t i = 0; i < len; ++i) {
    dst[i] = SPI.transfer(0x00);
  }

  pmod_acl_spi_deselect();
  SPI.endTransaction();
}

static void acl2_write_reg(uint8_t reg, uint8_t value) {
  SPI.beginTransaction(acl2_spi_settings());
  pmod_acl_spi_select();
  SPI.transfer(0x0A);
  SPI.transfer(reg);
  SPI.transfer(value);
  pmod_acl_spi_deselect();
  SPI.endTransaction();
}

static bool acl2_begin(void) {
  pmod_acl_spi_begin();
  delay(10);

  if (acl2_read_reg(0x00) != 0xAD) {
    return false;
  }

  // Standby while configuring, then 8 g range, 100 Hz ODR, measurement mode.
  acl2_write_reg(0x2D, 0x00);
  acl2_write_reg(0x2C, 0x83);
  acl2_write_reg(0x2D, 0x02);

  return true;
}

static void acl2_read_axes(int16_t raw[3]) {
  uint8_t buf[6] = { 0, 0, 0, 0, 0, 0 };
  acl2_read_regs(0x0E, buf, sizeof(buf));

  raw[0] = (int16_t)((uint16_t)buf[0] | ((uint16_t)buf[1] << 8));
  raw[1] = (int16_t)((uint16_t)buf[2] | ((uint16_t)buf[3] << 8));
  raw[2] = (int16_t)((uint16_t)buf[4] | ((uint16_t)buf[5] << 8));
}
#endif

#if PMOD_ACL_ENABLED
static SPISettings acl_spi_settings(void) {
  return SPISettings(PMOD_ACL_SPI_HZ, MSBFIRST, SPI_MODE3);
}

static uint8_t acl_read_reg(uint8_t reg) {
  SPI.beginTransaction(acl_spi_settings());
  pmod_acl_spi_select();
  SPI.transfer(0x80 | (reg & 0x3F));
  const uint8_t value = SPI.transfer(0x00);
  pmod_acl_spi_deselect();
  SPI.endTransaction();

  return value;
}

static void acl_read_regs(uint8_t reg, uint8_t *dst, uint8_t len) {
  if (!dst || len == 0U) {
    return;
  }

  SPI.beginTransaction(acl_spi_settings());
  pmod_acl_spi_select();
  SPI.transfer(0xC0 | (reg & 0x3F));

  for (uint8_t i = 0; i < len; ++i) {
    dst[i] = SPI.transfer(0x00);
  }

  pmod_acl_spi_deselect();
  SPI.endTransaction();
}

static void acl_write_reg(uint8_t reg, uint8_t value) {
  SPI.beginTransaction(acl_spi_settings());
  pmod_acl_spi_select();
  SPI.transfer(reg & 0x3F);
  SPI.transfer(value);
  pmod_acl_spi_deselect();
  SPI.endTransaction();
}

static bool acl_begin(void) {
  pmod_acl_spi_begin();
  delay(10);

  if (acl_read_reg(0x00) != 0xE5) {
    return false;
  }

  // Standby while configuring, then 100 Hz, full-resolution, +/-16 g measure.
  acl_write_reg(0x2D, 0x00);
  acl_write_reg(0x2C, 0x0A);
  acl_write_reg(0x31, 0x0B);
  acl_write_reg(0x2D, 0x08);

  return true;
}

static void acl_read_axes(int16_t raw[3]) {
  uint8_t buf[6] = { 0, 0, 0, 0, 0, 0 };
  acl_read_regs(0x32, buf, sizeof(buf));

  raw[0] = (int16_t)((uint16_t)buf[0] | ((uint16_t)buf[1] << 8));
  raw[1] = (int16_t)((uint16_t)buf[2] | ((uint16_t)buf[3] << 8));
  raw[2] = (int16_t)((uint16_t)buf[4] | ((uint16_t)buf[5] << 8));
}
#endif

static bool i2c_probe(TwoWire &bus, uint8_t address) {
  bus.beginTransmission(address);
  return bus.endTransmission() == 0;
}

static bool i2c_write_u8(TwoWire &bus, uint8_t address, uint8_t reg, uint8_t value) {
  bus.beginTransmission(address);
  bus.write(reg);
  bus.write(value);
  return bus.endTransmission() == 0;
}

static bool i2c_read_bytes(TwoWire &bus, uint8_t address, uint8_t reg, uint8_t *data, uint8_t len) {
  if (!data || len == 0U) {
    return false;
  }

  bus.beginTransmission(address);
  bus.write(reg);

  // The CMPS2/MMC34160PJ path tolerates a STOP between the register-pointer
  // write and the following read. Using a STOP here is more robust on the
  // Teensy 4.1 Wire1 bench wiring than holding a repeated-start transaction.
  if (bus.endTransmission() != 0) {
    return false;
  }

  if (bus.requestFrom(address, len) != len) {
    return false;
  }

  for (uint8_t i = 0; i < len; ++i) {
    if (!bus.available()) {
      return false;
    }

    data[i] = (uint8_t)bus.read();
  }

  return true;
}

static bool i2c_read_u8(TwoWire &bus, uint8_t address, uint8_t reg, uint8_t *value) {
  return i2c_read_bytes(bus, address, reg, value, 1U);
}

static void print_i2c_address(uint8_t address) {
  Serial.print(F("0x"));

  if (address < 0x10U) {
    Serial.print('0');
  }

  Serial.print(address, HEX);
}

static void print_i2c_scan_bus(TwoWire &bus, const __FlashStringHelper *name) {
  uint8_t found = 0;

  Serial.print(F("I2C_SCAN,"));
  Serial.print(name);
  Serial.println(F(",BEGIN"));

  for (uint8_t address = 0x03U; address <= 0x77U; ++address) {
    bus.beginTransmission(address);
    const uint8_t rc = bus.endTransmission();

    if (rc == 0U) {
      Serial.print(F("I2C_SCAN,"));
      Serial.print(name);
      Serial.print(',');
      print_i2c_address(address);
      Serial.println();
      ++found;
    }
  }

  if (found == 0U) {
    Serial.print(F("I2C_SCAN,"));
    Serial.print(name);
    Serial.println(F(",NONE"));
  }

  Serial.print(F("I2C_SCAN,"));
  Serial.print(name);
  Serial.print(F(",END,count="));
  Serial.println(found);
}

#if LIS3DH_ENABLED
static bool lis3dh_begin_at(uint8_t address) {
  if (!lis3dh.begin(address)) {
    return false;
  }

  lis3dh.setRange(LIS3DH_RANGE_16_G);
  lis3dh.setDataRate(LIS3DH_DATARATE_100_HZ);
  lis3dh_active_i2c_addr = address;

  return true;
}
#endif

#if PMOD_CMPS2_ENABLED
static bool pmod_cmps2_start_measurement(uint32_t now_ms) {
  if (!i2c_write_u8(
        Wire1,
        PMOD_CMPS2_I2C_ADDR,
        CMPS2_REG_CONTROL0,
        CMPS2_CONTROL0_TAKE_MEASUREMENT)) {
    cmps2_measurement_pending = false;
    cmps2_runtime_status = 2U;
    return false;
  }

  cmps2_measurement_pending = true;
  cmps2_measurement_started_ms = now_ms;
  cmps2_ready_after_ms = now_ms + PMOD_CMPS2_MEASUREMENT_TIME_MS;
  cmps2_runtime_status = 3U;

  return true;
}

static bool pmod_cmps2_set_sensor(void) {
  return i2c_write_u8(
    Wire1,
    PMOD_CMPS2_I2C_ADDR,
    CMPS2_REG_CONTROL0,
    CMPS2_CONTROL0_SET_SENSOR);
}

static bool pmod_cmps2_begin(uint32_t now_ms) {
  cmps2_measurement_pending = false;
  cmps2_product_id = 0U;
  cmps2_init_status = 1U;
  cmps2_runtime_status = 1U;
  bool product_id_verified = false;

  if (!i2c_probe(Wire1, PMOD_CMPS2_I2C_ADDR)) {
    cmps2_init_status = 2U;
    return false;
  }

  if (i2c_read_u8(Wire1, PMOD_CMPS2_I2C_ADDR, CMPS2_REG_PRODUCT_ID, &cmps2_product_id)) {
    product_id_verified = true;
  } else {
    cmps2_init_status = 3U;
  }

  if (product_id_verified && cmps2_product_id != CMPS2_EXPECTED_PRODUCT_ID) {
    cmps2_init_status = 4U;
    return false;
  }

  if (!pmod_cmps2_set_sensor()) {
    cmps2_init_status = 8U;
    return false;
  }

  delay(1);

  if (!pmod_cmps2_start_measurement(now_ms)) {
    cmps2_init_status = 5U;
    return false;
  }

  cmps2_init_status = product_id_verified ? 6U : 7U;
  return true;
}

static float pmod_cmps2_counts_to_ut(uint16_t raw_counts) {
  return ((float)raw_counts - PMOD_CMPS2_ZERO_FIELD_COUNTS) *
         PMOD_CMPS2_UT_PER_COUNT;
}

static float heading_deg_from_xy(float x_uT, float y_uT) {
  if (!is_finite_f(x_uT) || !is_finite_f(y_uT)) {
    return NAN;
  }

  float heading = atan2f(y_uT, x_uT) * (180.0f / 3.14159265358979323846f);

  if (heading < 0.0f) {
    heading += 360.0f;
  }

  return heading;
}
#endif

/*
sensors_begin(...)
------------------------------------------------------------------------------
ROLE
  Initialize all enabled sensors and publish boot health flags.

INPUT CONTRACT
  state must refer to the shared SystemState object. I2C pins and bus hardware
  must match board wiring.

OUTPUT CONTRACT
  state.health fields are set according to hardware initialization results.
  Return value is true if at least one enabled sensor initializes successfully.

MECHANISM
  1. Start Wire.
  2. Attempt BMP5xx initialization at supported addresses.
  3. Configure BMP5xx oversampling, IIR filter, output rate, and pressure mode.
  4. Attempt BMI088 accelerometer and gyroscope initialization.
  5. Attempt the selected auxiliary accelerometer initialization.
  6. Return aggregate hardware availability.

FAILURE BEHAVIOR
  Partial initialization is allowed. Failed sensors publish invalid snapshots
  during runtime and appear in telemetry warning masks.

DETERMINISM
  Bounded boot-time hardware initialization. No runtime retry loop. No dynamic
  allocation by project code.
*/
bool sensors_begin(SystemState &state) {
  // One shared I2C bus is brought up before any device-specific initialization.
  Wire.begin();
  Wire.setClock(I2C_SENSOR_CLOCK_HZ);

  // Wire1 is reserved for added Pmods such as CMPS2. Wire2 is initialized so the
  // diagnostic scanner can verify that no unexpected devices are present there.
  Wire1.begin();
  Wire1.setClock(I2C_SENSOR_CLOCK_HZ);
  Wire2.begin();
  Wire2.setClock(I2C_SENSOR_CLOCK_HZ);

#if BMP5XX_ENABLED
  if (bmp.begin(0x46, &Wire) || bmp.begin(0x47, &Wire)) {
    state.health.bmp_ok = true;

    // These BMP settings trade modest latency for cleaner pressure output at the
    // firmware's 50 Hz scheduler rate.
    bmp.setTemperatureOversampling(BMP5XX_OVERSAMPLING_2X);
    bmp.setPressureOversampling(BMP5XX_OVERSAMPLING_16X);
    bmp.setIIRFilterCoeff(BMP5XX_IIR_FILTER_COEFF_3);
    bmp.setOutputDataRate(BMP5XX_ODR_50_HZ);
    bmp.setPowerMode(BMP5XX_POWERMODE_NORMAL);
    bmp.enablePressure(true);
  }
#else
  state.health.bmp_ok = false;
#endif

#if BMI088_ENABLED
  state.health.bmi_accel_ok = (accel.begin() >= 0);
  state.health.bmi_gyro_ok = (gyro.begin() >= 0);
#else
  state.health.bmi_accel_ok = false;
  state.health.bmi_gyro_ok = false;
#endif

#if LIS2DU12_ENABLED
  if (lis.begin() == 0) {
    lis.Enable_X();
    state.health.lis_ok = true;
  } else {
    state.health.lis_ok = false;
  }
#elif LIS3DH_ENABLED
  lis3dh_active_i2c_addr = 0U;

  if (lis3dh_begin_at(LIS3DH_I2C_ADDR) ||
      (LIS3DH_I2C_ADDR_ALT != LIS3DH_I2C_ADDR && lis3dh_begin_at(LIS3DH_I2C_ADDR_ALT))) {
    state.health.lis_ok = true;
  } else {
    state.health.lis_ok = false;
  }
#else
  state.health.lis_ok = false;
#endif

#if PMOD_CMPS2_ENABLED
  state.health.mag_ok = pmod_cmps2_begin(millis());
#else
  state.health.mag_ok = false;
#endif

#if PMOD_ACL2_ENABLED
  state.health.pmod_accel_ok = acl2_begin();
  state.pmod_accel.kind = state.health.pmod_accel_ok ?
    PmodAccelKind::ACL2_ADXL362 : PmodAccelKind::NONE;
#elif PMOD_ACL_ENABLED
  state.health.pmod_accel_ok = acl_begin();
  state.pmod_accel.kind = state.health.pmod_accel_ok ?
    PmodAccelKind::ACL_ADXL345 : PmodAccelKind::NONE;
#else
  state.health.pmod_accel_ok = false;
  state.pmod_accel.kind = PmodAccelKind::NONE;
#endif

  return state.health.bmp_ok ||
         state.health.bmi_accel_ok ||
         state.health.bmi_gyro_ok ||
         state.health.lis_ok ||
         state.health.mag_ok ||
         state.health.pmod_accel_ok;
}

/*
sensors_print_status(...)
------------------------------------------------------------------------------
ROLE
  Print boot-time hardware availability in compact human-readable form.

INPUT CONTRACT
  state.health should already have been populated by sensors_begin(...).

OUTPUT CONTRACT
  Serial receives one status line per core or optional sensor group. SystemState
  is not modified.

MECHANISM
  1. Print BMP5xx health.
  2. Print BMI088 accelerometer health.
  3. Print BMI088 gyroscope health.
  4. Print selected auxiliary accelerometer health.
  5. Print optional Pmod accelerometer and CMPS2 health.

FAILURE BEHAVIOR
  No recovery is attempted. This function only reports existing health flags.

DETERMINISM
  Bounded Serial output. No loops. No sensor transactions.
*/
void sensors_print_status(const SystemState &state) {
  Serial.print(F("[ BMP5xx init ] : "));
  Serial.println(state.health.bmp_ok ? F("OK") : F("FAIL"));

  Serial.print(F("[ BMI088 accel ] : "));
  Serial.println(state.health.bmi_accel_ok ? F("OK") : F("FAIL"));

  Serial.print(F("[ BMI088 gyro  ] : "));
  Serial.println(state.health.bmi_gyro_ok ? F("OK") : F("FAIL"));

#if LIS3DH_ENABLED
  Serial.print(F("[ LIS3DH  ] : "));
#elif LIS2DU12_ENABLED
  Serial.print(F("[ LIS2DU12 ] : "));
#else
  Serial.print(F("[ Aux accel ] : "));
#endif
  Serial.println(state.health.lis_ok ? F("OK") : F("FAIL"));

  Serial.print(F("[ Pmod accel ] : "));
  Serial.println(state.health.pmod_accel_ok ? F("OK") : F("DISABLED/FAIL"));

  Serial.print(F("[ Pmod CMPS2 ] : "));
  Serial.println(state.health.mag_ok ? F("OK") : F("DISABLED/FAIL"));
}

uint8_t sensors_lis3dh_i2c_address(void) {
#if LIS3DH_ENABLED
  return lis3dh_active_i2c_addr;
#else
  return 0U;
#endif
}

uint8_t sensors_pmod_cmps2_product_id(void) {
#if PMOD_CMPS2_ENABLED
  return cmps2_product_id;
#else
  return 0U;
#endif
}

uint8_t sensors_pmod_cmps2_init_status(void) {
#if PMOD_CMPS2_ENABLED
  return cmps2_init_status;
#else
  return 0U;
#endif
}

uint8_t sensors_pmod_cmps2_runtime_status(void) {
#if PMOD_CMPS2_ENABLED
  return cmps2_runtime_status;
#else
  return 0U;
#endif
}

/*
sensors_print_i2c_scan(...)
------------------------------------------------------------------------------
ROLE
  Operator-commanded diagnostic scan of all Teensy 4.1 I2C buses used or
  reserved by this firmware.

DETERMINISM
  Bounded diagnostic loop over the valid 7-bit I2C address range on each bus.
  This must remain a command/bench diagnostic, not a runtime flight-loop action.
*/
void sensors_print_i2c_scan(void) {
#if I2C_SCANNER_ENABLED
  sensors_i2c_scan_all();
#else
  Serial.println(F("I2C_SCAN,DISABLED"));
#endif
}

void sensors_i2c_scan_all(void) {
#if I2C_SCANNER_ENABLED
  print_i2c_scan_bus(Wire, F("Wire"));
  print_i2c_scan_bus(Wire1, F("Wire1"));
  print_i2c_scan_bus(Wire2, F("Wire2"));
#else
  Serial.println(F("I2C_SCAN,DISABLED"));
#endif
}

/*
sensors_bmp_data_ready_within(...)
------------------------------------------------------------------------------
ROLE
  Boot-only diagnostic for BMP5xx data-ready behavior.

INPUT CONTRACT
  timeout_ms is the maximum diagnostic wait duration.

OUTPUT CONTRACT
  Returns true if BMP data-ready becomes true before timeout.

MECHANISM
  1. Capture start time.
  2. Poll bmp.dataReady().
  3. Delay 1 ms between polls.
  4. Return false if timeout expires.

FAILURE BEHAVIOR
  Timeout returns false without mutating SystemState.

DETERMINISM
  Bounded blocking loop. This function must not be called from the flight runtime
  path.
*/
bool sensors_bmp_data_ready_within(uint32_t timeout_ms) {
#if BMP5XX_ENABLED
  const uint32_t t0 = millis();

  while ((millis() - t0) < timeout_ms) {
    if (bmp.dataReady()) return true;
    delay(1);
  }

  return false;
#else
  (void)timeout_ms;
  return false;
#endif
}

/*
sensors_poll_baro(...)
------------------------------------------------------------------------------
ROLE
  Publish one BMP5xx barometer snapshot.

INPUT CONTRACT
  state must refer to the shared SystemState object. now_ms must be current
  millis() time. state.cfg.sea_level_hpa should be finite and positive.

OUTPUT CONTRACT
  state.baro.t_ms and t_us are updated for the acquisition attempt. updated is
  cleared before acquisition and asserted only after a valid new sample. valid is
  true only after successful finite temperature, pressure, and altitude outputs.

MECHANISM
  1. Timestamp the attempt.
  2. Clear updated flag.
  3. Reject missing BMP hardware.
  4. Attempt exactly one BMP reading.
  5. Convert pressure from Pa to hPa.
  6. Convert hPa pressure to altitude.
  7. Validate numerical outputs.
  8. Publish payload and increment sequence on success.

FAILURE BEHAVIOR
  Failed hardware initialization or failed reading sets valid=false and returns.
  Downstream readers must ignore payload unless valid is true.

DETERMINISM
  One hardware transaction attempt. No retry loop. No dynamic allocation.
*/
bool sensors_poll_baro(SystemState &state, uint32_t now_ms) {
#if BMP5XX_ENABLED
  const uint32_t now_us = micros();

  state.baro.t_ms = now_ms;
  state.baro.t_us = now_us;
  state.baro.updated = false;

  if (!state.health.bmp_ok) {
    state.baro.valid = false;
    return true;
  }

  if (!bmp.performReading()) {
    state.baro.valid = false;
    return true;
  }

  // The Adafruit BMP driver reports pressure in pascals; the rest of this
  // firmware standardizes on hectopascals for atmospheric calculations and
  // logging.
  const float press_hpa = bmp.pressure / 100.0f;
  const float temp_c = bmp.temperature;
  const float alt_m = pressure_to_altitude_m(press_hpa, state.cfg.sea_level_hpa);

  state.baro.valid =
    is_finite_f(press_hpa) &&
    is_finite_f(temp_c) &&
    is_finite_f(alt_m);

  if (state.baro.valid) {
    state.baro.updated = true;
    ++state.baro.seq;

    state.baro.temp_c = temp_c;
    state.baro.press_hpa = press_hpa;
    state.baro.alt_m = alt_m;
  }

  return true;
#else
  const uint32_t now_us = micros();
  state.baro.t_ms = now_ms;
  state.baro.t_us = now_us;
  state.baro.updated = false;
  state.baro.valid = false;
  return true;
#endif
}

/*
sensors_poll_imu(...)
------------------------------------------------------------------------------
ROLE
  Publish one BMI088 IMU snapshot.

INPUT CONTRACT
  state must refer to the shared SystemState object. now_ms must be current
  millis() time.

OUTPUT CONTRACT
  state.imu timestamps and updated flag are refreshed. valid is true when either
  accelerometer or gyroscope stream provides finite data.

MECHANISM
  1. Timestamp the attempt.
  2. Initialize local values to NAN.
  3. Read accelerometer once if available.
  4. Read gyroscope once if available.
  5. Validate accel and gyro streams independently.
  6. Publish available values when at least one stream is valid.
  7. Compute acceleration norm only when accelerometer data is valid.

FAILURE BEHAVIOR
  If both streams fail or are unavailable, state.imu.valid becomes false.

DETERMINISM
  At most one accelerometer read and one gyro read. No retry loop. No dynamic
  allocation.
*/
bool sensors_poll_imu(SystemState &state, uint32_t now_ms) {
#if BMI088_ENABLED
  const uint32_t now_us = micros();

  state.imu.t_ms = now_ms;
  state.imu.t_us = now_us;
  state.imu.updated = false;

  bool accel_valid = false;
  bool gyro_valid = false;

  float ax = NAN;
  float ay = NAN;
  float az = NAN;
  float gx = NAN;
  float gy = NAN;
  float gz = NAN;

  if (state.health.bmi_accel_ok) {
    // Exactly one read is attempted per cycle so timing remains bounded and the
    // publication semantics stay simple.
    accel.readSensor();
    ax = accel.getAccelX_mss();
    ay = accel.getAccelY_mss();
    az = accel.getAccelZ_mss();
    accel_valid = is_finite_f(ax) && is_finite_f(ay) && is_finite_f(az);
  }

  if (state.health.bmi_gyro_ok) {
    gyro.readSensor();
    gx = gyro.getGyroX_rads();
    gy = gyro.getGyroY_rads();
    gz = gyro.getGyroZ_rads();
    gyro_valid = is_finite_f(gx) && is_finite_f(gy) && is_finite_f(gz);
  }

  state.imu.valid = accel_valid || gyro_valid;

  if (!state.imu.valid) {
    return true;
  }

  state.imu.updated = true;
  ++state.imu.seq;

  state.imu.ax = ax;
  state.imu.ay = ay;
  state.imu.az = az;
  state.imu.gx = gx;
  state.imu.gy = gy;
  state.imu.gz = gz;
  state.imu.a_norm = accel_valid ? sqrtf(ax * ax + ay * ay + az * az) : NAN;

  return true;
#else
  (void)now_ms;
  state.imu.updated = false;
  state.imu.valid = false;
  return true;
#endif
}

/*
sensors_poll_aux(...)
------------------------------------------------------------------------------
ROLE
  Publish one selected auxiliary accelerometer snapshot.

INPUT CONTRACT
  state must refer to the shared SystemState object. now_ms must be current
  millis() time.

OUTPUT CONTRACT
  state.aux timestamps and updated flag are refreshed. valid is true only when
  converted x/y/z acceleration values are finite.

MECHANISM
  1. Timestamp the attempt.
  2. Reject missing auxiliary accelerometer hardware.
  3. Read raw integer axes once.
  4. Read sensitivity once.
  5. Convert raw counts to m/s^2.
  6. Validate converted values.
  7. Publish payload and sequence on success.

FAILURE BEHAVIOR
  Failed initialization or invalid conversion sets state.aux.valid=false.

DETERMINISM
  One raw-axis read and one sensitivity read. No retry loop. No dynamic allocation.
*/
bool sensors_poll_aux(SystemState &state, uint32_t now_ms) {
  const uint32_t now_us = micros();

  state.aux.t_ms = now_ms;
  state.aux.t_us = now_us;
  state.aux.updated = false;

  if (!state.health.lis_ok) {
    state.aux.valid = false;
    return true;
  }

#if LIS2DU12_ENABLED
  int16_t raw[3] = { 0, 0, 0 };
  float sensitivity = 0.0f;

  lis.Get_X_AxesRaw(raw);
  lis.Get_X_Sensitivity(&sensitivity);

  // Sensitivity is typically reported in mg/LSB, so the conversion is:
  //   raw * sensitivity -> mg
  //   mg * 0.001        -> g
  //   g * 9.80665       -> m/s^2
  const float ax = raw[0] * sensitivity * 0.001f * 9.80665f;
  const float ay = raw[1] * sensitivity * 0.001f * 9.80665f;
  const float az = raw[2] * sensitivity * 0.001f * 9.80665f;

  state.aux.valid = is_finite_f(ax) && is_finite_f(ay) && is_finite_f(az);

  if (state.aux.valid) {
    state.aux.updated = true;
    ++state.aux.seq;

    state.aux.ax = ax;
    state.aux.ay = ay;
    state.aux.az = az;
    state.aux.a_norm = sqrtf(ax * ax + ay * ay + az * az);
  }

  return true;
#elif LIS3DH_ENABLED
  sensors_event_t event;
  if (!lis3dh.getEvent(&event)) {
    state.aux.valid = false;
    return true;
  }

  const float ax = event.acceleration.x;
  const float ay = event.acceleration.y;
  const float az = event.acceleration.z;

  state.aux.valid = is_finite_f(ax) && is_finite_f(ay) && is_finite_f(az);

  if (state.aux.valid) {
    state.aux.updated = true;
    ++state.aux.seq;

    state.aux.ax = ax;
    state.aux.ay = ay;
    state.aux.az = az;
    state.aux.a_norm = sqrtf(ax * ax + ay * ay + az * az);
  }

  return true;
#else
  state.aux.valid = false;
  return true;
#endif
}

/*
sensors_poll_pmod_accel(...)
------------------------------------------------------------------------------
ROLE
  Publish one optional Digilent Pmod ACL2/ACL accelerometer snapshot.

DESIGN NOTE
  This path is observational. It does not replace the BMI088 IMU source used by
  attitude, vertical acceleration, estimator, phase, safety, or policy logic.

DETERMINISM
  At most one fixed-size SPI burst read per call when enabled. No retry loop,
  heap allocation, or blocking conversion wait.
*/
bool sensors_poll_pmod_accel(SystemState &state, uint32_t now_ms) {
#if PMOD_ACL2_ENABLED || PMOD_ACL_ENABLED
  const uint32_t now_us = micros();

  state.pmod_accel.t_ms = now_ms;
  state.pmod_accel.t_us = now_us;
  state.pmod_accel.updated = false;

  if (!state.health.pmod_accel_ok) {
    state.pmod_accel.valid = false;
    state.pmod_accel.kind = PmodAccelKind::NONE;
    return true;
  }

  int16_t raw[3] = { 0, 0, 0 };
  float scale = NAN;

#if PMOD_ACL2_ENABLED
  acl2_read_axes(raw);
  scale = PMOD_ACL2_MPS2_PER_LSB;
  state.pmod_accel.kind = PmodAccelKind::ACL2_ADXL362;
#elif PMOD_ACL_ENABLED
  acl_read_axes(raw);
  scale = PMOD_ACL_MPS2_PER_LSB;
  state.pmod_accel.kind = PmodAccelKind::ACL_ADXL345;
#endif

  const float ax = (float)raw[0] * scale;
  const float ay = (float)raw[1] * scale;
  const float az = (float)raw[2] * scale;
  const float a_norm = sqrtf(ax * ax + ay * ay + az * az);

  state.pmod_accel.valid =
    is_finite_f(ax) &&
    is_finite_f(ay) &&
    is_finite_f(az) &&
    is_finite_f(a_norm);

  if (state.pmod_accel.valid) {
    state.pmod_accel.updated = true;
    ++state.pmod_accel.seq;

    state.pmod_accel.raw_x = raw[0];
    state.pmod_accel.raw_y = raw[1];
    state.pmod_accel.raw_z = raw[2];
    state.pmod_accel.ax = ax;
    state.pmod_accel.ay = ay;
    state.pmod_accel.az = az;
    state.pmod_accel.a_norm = a_norm;
    state.pmod_accel.motion_bad = false;
  }

  return true;
#else
  (void)now_ms;
  state.pmod_accel.updated = false;
  state.pmod_accel.valid = false;
  state.pmod_accel.kind = PmodAccelKind::NONE;
  return true;
#endif
}

/*
sensors_poll_mag(...)
------------------------------------------------------------------------------
ROLE
  Publish one Pmod CMPS2 magnetometer snapshot when a non-blocking conversion is
  ready.

INPUT CONTRACT
  CMPS2 is wired to Wire1: SDA1 pin 17, SCL1 pin 16, 3.3 V, and GND. This
  snapshot is observability-only and must not drive control logic without later
  calibration and flight-like validation.

OUTPUT CONTRACT
  state.mag.updated is true only when a new six-byte magnetic-field sample has
  been published. state.mag.t_ms/t_us record publication time, not mere polling
  time, so freshness diagnostics are not reset by a conversion that is still
  pending.

MECHANISM
  1. Start a measurement when none is pending.
  2. Return without blocking until the conversion-ready time has elapsed.
  3. Check the CMPS2/MMC34160PJ measurement-done bit.
  4. Read X/Y/Z unsigned counts.
  5. Convert centered counts to microtesla using the 16-bit sensitivity.
  6. Publish raw counts, calibrated vector, norm, heading, and interference flag.
  7. Start the next measurement for a later scheduler pass.

FAILURE BEHAVIOR
  Failed transactions invalidate only the magnetometer snapshot. Existing baro,
  IMU, estimator, policy, safety, and actuator behavior is unchanged.

DETERMINISM
  At most a small fixed number of I2C transactions per call. No conversion wait,
  retry loop, heap allocation, or dynamic driver object.
*/
bool sensors_poll_mag(SystemState &state, uint32_t now_ms) {
#if PMOD_CMPS2_ENABLED
  state.mag.updated = false;

  if (!state.health.mag_ok) {
    state.mag.t_ms = now_ms;
    state.mag.t_us = micros();
    state.mag.valid = false;
    cmps2_runtime_status = 1U;
    return true;
  }

  if (!cmps2_measurement_pending) {
    if (!pmod_cmps2_start_measurement(now_ms)) {
      state.mag.t_ms = now_ms;
      state.mag.t_us = micros();
      state.mag.valid = false;
    }

    return true;
  }

  if ((int32_t)(now_ms - cmps2_ready_after_ms) < 0) {
    cmps2_runtime_status = 3U;
    return true;
  }

  uint8_t status = 0U;

  if (!i2c_read_u8(Wire1, PMOD_CMPS2_I2C_ADDR, CMPS2_REG_STATUS, &status)) {
    cmps2_measurement_pending = false;
    state.mag.t_ms = now_ms;
    state.mag.t_us = micros();
    state.mag.valid = false;
    cmps2_runtime_status = 4U;
    return true;
  }

  if ((status & CMPS2_STATUS_MEAS_DONE) == 0U) {
    if ((now_ms - cmps2_measurement_started_ms) >= PMOD_CMPS2_READY_TIMEOUT_MS) {
      cmps2_measurement_pending = false;
      state.mag.t_ms = now_ms;
      state.mag.t_us = micros();
      state.mag.valid = false;
      cmps2_runtime_status = 5U;
    } else {
      cmps2_runtime_status = 3U;
    }

    return true;
  }

  uint8_t raw[6] = { 0, 0, 0, 0, 0, 0 };

  if (!i2c_read_bytes(Wire1, PMOD_CMPS2_I2C_ADDR, CMPS2_REG_XOUT_L, raw, sizeof(raw))) {
    cmps2_measurement_pending = false;
    state.mag.t_ms = now_ms;
    state.mag.t_us = micros();
    state.mag.valid = false;
    cmps2_runtime_status = 6U;
    return true;
  }

  const uint16_t raw_x = (uint16_t)raw[0] | ((uint16_t)raw[1] << 8);
  const uint16_t raw_y = (uint16_t)raw[2] | ((uint16_t)raw[3] << 8);
  const uint16_t raw_z = (uint16_t)raw[4] | ((uint16_t)raw[5] << 8);

  const float x_uT = pmod_cmps2_counts_to_ut(raw_x);
  const float y_uT = pmod_cmps2_counts_to_ut(raw_y);
  const float z_uT = pmod_cmps2_counts_to_ut(raw_z);

  const float cal_x = (x_uT - PMOD_CMPS2_CAL_OFFSET_X_UT) * PMOD_CMPS2_CAL_SCALE_X;
  const float cal_y = (y_uT - PMOD_CMPS2_CAL_OFFSET_Y_UT) * PMOD_CMPS2_CAL_SCALE_Y;
  const float cal_z = (z_uT - PMOD_CMPS2_CAL_OFFSET_Z_UT) * PMOD_CMPS2_CAL_SCALE_Z;
  const float norm_uT = sqrtf(cal_x * cal_x + cal_y * cal_y + cal_z * cal_z);
  const float heading_deg = heading_deg_from_xy(cal_x, cal_y);

  state.mag.valid =
    is_finite_f(cal_x) &&
    is_finite_f(cal_y) &&
    is_finite_f(cal_z) &&
    is_finite_f(norm_uT);

  state.mag.t_ms = now_ms;
  state.mag.t_us = micros();

  if (state.mag.valid) {
    state.mag.updated = true;
    ++state.mag.seq;

    state.mag.raw_x = (float)raw_x;
    state.mag.raw_y = (float)raw_y;
    state.mag.raw_z = (float)raw_z;
    state.mag.cal_x = cal_x;
    state.mag.cal_y = cal_y;
    state.mag.cal_z = cal_z;
    state.mag.norm_uT = norm_uT;
    state.mag.heading_deg = heading_deg;
    state.mag.interference =
      norm_uT < PMOD_CMPS2_FIELD_NORM_MIN_UT ||
      norm_uT > PMOD_CMPS2_FIELD_NORM_MAX_UT;
  } else {
    cmps2_runtime_status = 7U;
  }

  cmps2_measurement_pending = false;
  (void)pmod_cmps2_start_measurement(now_ms);

  if (state.mag.valid) {
    cmps2_runtime_status = 8U;
  }

  return true;
#else
  (void)now_ms;
  state.mag.updated = false;
  state.mag.valid = false;
  return true;
#endif
}

/*
sensors_calibrate_baro_base(...)
------------------------------------------------------------------------------
ROLE
  Capture an averaged local barometer baseline pressure.

INPUT CONTRACT
  state must refer to the shared SystemState object. BMP5xx must be initialized.
  sample_count should be positive. This routine is intended for boot or ground
  command use, not flight-loop runtime.

OUTPUT CONTRACT
  On success, state.cfg.baro_baseline_hpa receives the average pressure in hPa,
  state.cfg.valid is asserted, and true is returned.

MECHANISM
  1. Reject unavailable barometer or zero sample count.
  2. Repeatedly poll one barometer sample.
  3. Accumulate finite pressure samples in hPa.
  4. Delay between samples because this is a deliberate calibration routine.
  5. Publish average baseline pressure.

FAILURE BEHAVIOR
  If no valid samples are collected, baseline remains unchanged and false is
  returned.

DETERMINISM
  Bounded blocking loop with sample_count iterations. No dynamic allocation.
*/
bool sensors_calibrate_baro_base(SystemState &state, uint16_t sample_count) {
  if (!state.health.bmp_ok) return false;
  if (sample_count == 0U) return false;

  float sum_hpa = 0.0f;
  uint16_t count = 0U;

  for (uint16_t i = 0; i < sample_count; ++i) {
    const uint32_t now_ms = millis();

    sensors_poll_baro(state, now_ms);

    if (state.baro.valid && is_finite_f(state.baro.press_hpa)) {
      sum_hpa += state.baro.press_hpa;
      ++count;
    }

    delay(BARO_CALIB_SAMPLE_DELAY_MS);
  }

  if (count == 0U) {
    return false;
  }

  state.cfg.baro_baseline_hpa = sum_hpa / (float)count;
  state.cfg.valid = true;

  return true;
}
