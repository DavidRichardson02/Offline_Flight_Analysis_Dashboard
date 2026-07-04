#include "actuator.h"

#include "config.h"
#include "math_utils.h"

#if defined(ARDUINO_TEENSY41) || defined(TEENSYDUINO)
#include <PWMServo.h>
static PWMServo servo;
#define ACTUATOR_BACKEND_PWMSERVO 1
#else
#include <Servo.h>
static Servo servo;
#define ACTUATOR_BACKEND_PWMSERVO 0
#endif

/*
actuator.cpp
===============================================================================
PURPOSE
  Own servo attachment, command mapping, and idle forcing.

IMPLEMENTATION NOTE
  This implementation stores commands as pulse-equivalent microseconds. Teensy
  PWMServo does not expose writeMicroseconds(), so the backend wrapper maps the
  requested pulse into the attach(min,max) angle domain while preserving g_last_us
  as the requested pulse-width evidence.
===============================================================================
*/

static ActuatorConfig g_cfg = 
{
  SERVO_US_MIN_DEFAULT,
  SERVO_US_MAX_DEFAULT,
  SERVO_US_IDLE_DEFAULT
};

// Attachment state and last-command telemetry are kept private so there is one
// authoritative actuator writer and one authoritative record of what was sent.
static bool g_attached = false;
static int g_last_us = SERVO_US_IDLE_DEFAULT;

/*
servo_write_pulse_us(...)
------------------------------------------------------------------------------
ROLE
  Write a pulse-equivalent actuator command through the selected servo backend.

INPUT CONTRACT
  us must already be clamped into the configured safe span.

OUTPUT CONTRACT
  Teensy PWMServo receives an angle equivalent to the requested pulse within the
  configured attach(min,max) range. Standard Servo backends receive the pulse
  directly in microseconds.
*/
static void servo_write_pulse_us(int us) {
#if ACTUATOR_BACKEND_PWMSERVO
  const int span_us = g_cfg.servo_us_max - g_cfg.servo_us_min;
  int angle_deg = 0;

  if (span_us > 0) {
    const float normalized =
      (float)(us - g_cfg.servo_us_min) / (float)span_us;
    angle_deg = (int)(normalized * 180.0f + 0.5f);
  }

  if (angle_deg < 0) angle_deg = 0;
  if (angle_deg > 180) angle_deg = 180;

  servo.write(angle_deg);
#else
  servo.writeMicroseconds(us);
#endif
}

/*
clamp_servo_us(...)
------------------------------------------------------------------------------
ROLE
  Clamp a pulse-equivalent servo command into the configured safe span.

INPUT CONTRACT
  g_cfg must contain a sensible min/max ordering. us may be outside span.

OUTPUT CONTRACT
  Returns a pulse-equivalent command within the configured travel limits.
*/
static int clamp_servo_us(int us) {
  if (us < g_cfg.servo_us_min) us = g_cfg.servo_us_min;
  if (us > g_cfg.servo_us_max) us = g_cfg.servo_us_max;
  return us;
}

/*
command01_to_us(...)
------------------------------------------------------------------------------
ROLE
  Convert normalized actuator command into equivalent pulse width.

INPUT CONTRACT
  command01 may be finite, non-finite, or outside [0,1]. clamp01 handles it.

OUTPUT CONTRACT
  Returns equivalent pulse within configured span.

MECHANISM
  1. Clamp normalized command to [0,1].
  2. Multiply by configured pulse span.
  3. Add configured minimum pulse.

FAILURE BEHAVIOR
  Non-finite command maps to zero command through clamp01.

DETERMINISM
  Constant-time scalar math. No loops. No hardware I/O. No dynamic allocation.
*/
static int command01_to_us(float command01) 
{
  // command01 is the control-law output in normalized actuator space. This
  // helper performs the affine map into the configured servo pulse domain.
  const float u = clamp01(command01);

  return (int)((float)g_cfg.servo_us_min   +   u * (float)(g_cfg.servo_us_max - g_cfg.servo_us_min)
  );
}

/*
actuator_begin(...)
------------------------------------------------------------------------------
ROLE
  Attach servo backend and immediately force idle output.

INPUT CONTRACT
  cfg should contain safe servo min, max, and idle settings.

OUTPUT CONTRACT
  Module configuration is stored, servo is attached, and idle is commanded.

MECHANISM
  1. Store actuator configuration.
  2. Attach servo backend to PIN_AIRBRAKE_SERVO.
  3. Mark backend attached.
  4. Force idle.

FAILURE BEHAVIOR
  Servo attach status is not explicitly reported by this backend.

DETERMINISM
  Bounded servo attach call. No loops. No dynamic allocation.
*/
void actuator_begin(const ActuatorConfig &cfg) 
{
  g_cfg = cfg;

  // Servo attachment is centralized here so no other module can inadvertently
  // change pins or reattach the device with different settings.
  servo.attach(PIN_AIRBRAKE_SERVO, g_cfg.servo_us_min, g_cfg.servo_us_max);
  g_attached = true;

  actuator_force_idle();
}

/*
actuator_force_idle(...)
------------------------------------------------------------------------------
ROLE
  Write configured idle output to the servo backend.

INPUT CONTRACT
  actuator_begin(...) should have been called.

OUTPUT CONTRACT
  If attached, servo output is set to idle and g_last_us records idle pulse.

MECHANISM
  1. Reject unattached backend.
  2. Clamp idle pulse-equivalent into the configured span.
  3. Write servo pulse width directly.
  4. Store idle equivalent pulse.

FAILURE BEHAVIOR
  Unattached backend returns without hardware write.

DETERMINISM
  Constant-time plus one servo write. No loops. No dynamic allocation.
*/
void actuator_force_idle(void) 
{
  if (!g_attached) return;

  const int us = clamp_servo_us(g_cfg.servo_us_idle);
  servo_write_pulse_us(us);
  g_last_us = us;
}

/*
actuator_write_command01(...)
------------------------------------------------------------------------------
ROLE
  Apply normalized actuator command if compile-time actuation is enabled.

INPUT CONTRACT
  command01 may be any float.

OUTPUT CONTRACT
  If actuation is compiled in and backend is attached, servo command is written.
  Otherwise idle is forced.

MECHANISM
  1. Enforce compile-time actuation gate.
  2. Reject unattached backend.
  3. Convert normalized command to pulse-equivalent.
  4. Clamp pulse-equivalent into the configured span.
  5. Write servo output and record telemetry pulse.

FAILURE BEHAVIOR
  Safe builds force idle. Non-finite commands clamp to zero.

DETERMINISM
  Constant-time plus one servo write. No loops. No dynamic allocation.
*/
void actuator_write_command01(float command01) 
{
#if ACTUATION_ENABLED
  if (!g_attached) return;

  const int us = clamp_servo_us(command01_to_us(command01));
  servo_write_pulse_us(us);
  g_last_us = us;
#else
  (void)command01;
  actuator_force_idle();
#endif
}

/*
actuator_last_us(...)
------------------------------------------------------------------------------
ROLE
  Report last equivalent pulse command for telemetry.

INPUT CONTRACT
  None.

OUTPUT CONTRACT
  Returns g_last_us.

MECHANISM
  1. Return stored pulse-equivalent value.

FAILURE BEHAVIOR
  No failure path exists.

DETERMINISM
  Constant-time. No loops. No hardware I/O. No dynamic allocation.
*/
int actuator_last_us(void) 
{
  return g_last_us;
}
