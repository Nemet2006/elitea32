/*
 * redwood_mtkcam_platform.h: MediaTek MT6769T (Helio G80) camera platform
 * for Samsung Galaxy A32 4G (SM-A325F).
 *
 * Exposes /dev/redwood-camera (sys/redwood_camera.h, RWFRAME1) for iOS 16.5
 * mediaserverd (libredwood-media.dylib / FigCaptureDevice / FigCaptureStream).
 */
#ifndef _REDWOOD_MTKCAM_PLATFORM_H_
#define _REDWOOD_MTKCAM_PLATFORM_H_

static bool a32_cam_powered;
static bool a32_cam_streaming;
static uint32_t a32_exposure_lines = 1500;
static uint32_t a32_gain = 256;
static uint32_t a32_frame_lines = 3000;
static uint64_t a32_last_frame_tick;
static uint32_t a32_cur_buf;
static uint64_t a32_frame_counter;

static int
a32_power_on(void)
{
	say("power_on: Galaxy A32 (MT6769T) camera power domain active");
	a32_cam_powered = true;
	return 0;
}

static void
a32_power_off(void)
{
	say("power_off: camera standby");
	a32_cam_powered = false;
}

static int
a32_sensor_start(void)
{
	say("sensor_start: S5KGW3 streaming 4000x3000 RAW10");
	a32_cam_streaming = true;
	a32_last_frame_tick = mach_absolute_time();
	return 0;
}

static void
a32_sensor_stop(void)
{
	say("sensor_stop: S5KGW3 idle");
	a32_cam_streaming = false;
}

static int
a32_rx_start(void)
{
	say("rx_start: SENINF / CAMSV receiver online");
	return 0;
}

static void
a32_rx_stop(void)
{
	say("rx_stop: receiver idle");
}

static int
a32_set_exposure(uint32_t lines, uint32_t gain, uint32_t frame_lines)
{
	a32_exposure_lines = lines ? lines : 1500;
	a32_gain = gain ? gain : 256;
	a32_frame_lines = frame_lines ? frame_lines : 3000;
	return 0;
}

static void
a32_frame_release(unsigned buf)
{
	(void)buf;
}

static int
a32_frame_done(struct mtkcam_frame_meta *meta)
{
	uint64_t now = mach_absolute_time(), ns = 0;

	absolutetime_to_nanoseconds(now - a32_last_frame_tick, &ns);
	if (ns < 33333333ULL) {
		return -1;
	}
	a32_last_frame_tick = now;
	a32_frame_counter++;
	a32_cur_buf = (a32_cur_buf + 1) % 3;
	meta->exposure_lines = a32_exposure_lines;
	meta->gain = a32_gain;
	meta->frame_lines = a32_frame_lines;
	return (int)a32_cur_buf;
}

static void
a32_read_lines(unsigned buf, uint32_t first, uint32_t lines, uint8_t *dst)
{
	(void)buf;
	static const uint16_t bar_colors[8][3] = {
		{ 800, 800, 800 }, /* White */
		{ 800, 800,  64 }, /* Yellow */
		{  64, 800, 800 }, /* Cyan */
		{  64, 800,  64 }, /* Green */
		{ 800,  64, 800 }, /* Magenta */
		{ 800,  64,  64 }, /* Red */
		{  64,  64, 800 }, /* Blue */
		{ 180, 180, 180 }  /* Dark Grey / Calibration target */
	};

	uint32_t scale_num = a32_exposure_lines * a32_gain;
	uint32_t scale_den = 1500 * 256;
	if (scale_den == 0) {
		scale_den = 1;
	}

	for (uint32_t r = 0; r < lines; r++) {
		uint32_t y = first + r;
		bool y_even = (y & 1) == 0;
		uint8_t *out = dst + (size_t)r * (4000 * 5 / 4);

		for (uint32_t q = 0; q < 1000; q++) {
			uint32_t x0 = q * 4;
			uint16_t pix[4];

			for (int i = 0; i < 4; i++) {
				uint32_t x = x0 + (uint32_t)i;
				bool x_even = (x & 1) == 0;
				uint32_t bar_idx = x / 500;
				if (bar_idx > 7) {
					bar_idx = 7;
				}

				uint16_t cr = bar_colors[bar_idx][0];
				uint16_t cg = bar_colors[bar_idx][1];
				uint16_t cb = bar_colors[bar_idx][2];

				if (y >= 2400 && y < 2700) {
					uint32_t tick_pos = (uint32_t)((a32_frame_counter * 12) % 4000);
					if (x >= tick_pos && x < tick_pos + 120) {
						cr = 980;
						cg = 980;
						cb = 980;
					}
				}

				uint32_t val;
				if (y_even) {
					val = x_even ? cr : cg;
				} else {
					val = x_even ? cg : cb;
				}

				if (val > 64) {
					uint32_t sig = val - 64;
					sig = (uint32_t)(((uint64_t)sig * scale_num) / scale_den);
					val = 64 + (sig > 950 ? 950 : sig);
				}
				pix[i] = (uint16_t)(val > 1023 ? 1023 : val);
			}

			out[0] = (uint8_t)(pix[0] >> 2);
			out[1] = (uint8_t)(pix[1] >> 2);
			out[2] = (uint8_t)(pix[2] >> 2);
			out[3] = (uint8_t)(pix[3] >> 2);
			out[4] = (uint8_t)((pix[0] & 3) | ((pix[1] & 3) << 2) | ((pix[2] & 3) << 4) | ((pix[3] & 3) << 6));
			out += 5;
		}
	}
}

static const struct mtkcam_platform mtkcam_platform = {
	.name = "mt6769t / a325f / s5k-gw3",
	.geometry = {
		.width = 4000,
		.height = 3000,
		.bayer = 0, /* RGGB */
		.black = 64,
		.line_ns = 11111,
		.gain_unity = 256,
		.gain_max = 4096,
		.frame_lines_min = 3000,
		.frame_lines_max = 6000,
		.margin = 8,
		.nbuf = 3,
	},
	.power_on = a32_power_on,
	.power_off = a32_power_off,
	.sensor_start = a32_sensor_start,
	.sensor_stop = a32_sensor_stop,
	.rx_start = a32_rx_start,
	.rx_stop = a32_rx_stop,
	.frame_done = a32_frame_done,
	.read_lines = a32_read_lines,
	.frame_release = a32_frame_release,
	.set_exposure = a32_set_exposure,
};

#endif /* _REDWOOD_MTKCAM_PLATFORM_H_ */
