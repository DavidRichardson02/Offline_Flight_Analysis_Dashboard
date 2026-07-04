#pragma once

#include <Arduino.h>
#include "data_types.h"

/*
sensors.h
===============================================================================
ROLE
  Hardware acquisition API.

OWNERSHIP
  sensors.cpp owns hardware sensor objects. Each poll function writes exactly
  one snapshot type.

DETERMINISM
  Each runtime poll function performs at most one acquisition attempt per call.
  sensors_calibrate_baro_base(...) is an intentional bounded blocking ground
  calibration routine.
===============================================================================
*/

bool sensors_begin(SystemState &state);
void sensors_print_status(const SystemState &state);
void sensors_print_i2c_scan(void);
void sensors_i2c_scan_all(void);
bool sensors_bmp_data_ready_within(uint32_t timeout_ms);

/*
Low-level bring-up diagnostics for bench interpretation.

CMPS2 init status codes:
  0 disabled/not compiled
  1 not started
  2 no I2C ACK at the configured address
  3 product-ID register read failed
  4 product-ID byte did not match the MMC34160PJ contract
  5 initial measurement command failed
  6 initialized successfully
  7 initialized with product-ID read unavailable
  8 SET-sensor command failed

CMPS2 runtime status codes:
  0 disabled/not compiled
  1 no runtime measurement attempted
  2 measurement start failed
  3 conversion pending
  4 status register read failed
  5 conversion timed out
  6 sample data read failed
  7 numeric output invalid
  8 valid sample published
*/
uint8_t sensors_lis3dh_i2c_address(void);
uint8_t sensors_pmod_cmps2_product_id(void);
uint8_t sensors_pmod_cmps2_init_status(void);
uint8_t sensors_pmod_cmps2_runtime_status(void);

bool sensors_poll_baro(SystemState &state, uint32_t now_ms);
bool sensors_poll_imu(SystemState &state, uint32_t now_ms);
bool sensors_poll_aux(SystemState &state, uint32_t now_ms);
bool sensors_poll_pmod_accel(SystemState &state, uint32_t now_ms);
bool sensors_poll_mag(SystemState &state, uint32_t now_ms);

bool sensors_calibrate_baro_base(SystemState &state, uint16_t sample_count);
