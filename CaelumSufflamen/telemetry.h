#pragma once

#include <Arduino.h>
#include "data_types.h"

/*
telemetry.h
===============================================================================
ROLE
  Stable CSV telemetry, status, diagnostics, and warning-mask construction.
===============================================================================
*/

void telemetry_print_header(void);
void telemetry_emit_tlm(const SystemState &state);
void telemetry_print_status(const SystemState &state);
void telemetry_print_plot_header(PlotMode mode);
void telemetry_emit_plot(const SystemState &state, uint32_t now_ms);
void telemetry_emit_diag(const SystemState &state, uint32_t now_ms);
uint32_t telemetry_warn_mask(const SystemState &state);
