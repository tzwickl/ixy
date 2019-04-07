#ifndef IXY_INTERRUPTS_H
#define IXY_INTERRUPTS_H

#include <stdint.h>
#include <stddef.h>
#include <time.h>
#include "driver/device.h"

struct interrupts {
	uint64_t last_time_checked;
    uint64_t interval;
	bool interrupt_enabled;
	size_t rx_pkts;
};

void check_interrupt(struct interrupts* interrupts, uint64_t time);

uint64_t get_monotonic_time();

#endif //IXY_INTERRUPTS_H
