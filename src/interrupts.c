#include "interrupts.h"
#include "libixy-vfio.h"

#include <stdio.h>

static double pps(uint64_t received_pkts, uint64_t elapsed_time_nanos) {
	return (double) received_pkts / ((double) elapsed_time_nanos / 1000000000.0);
}

// returns a timestamp in nanoseconds
// based on rdtsc on reasonably configured systems and is hence fast
uint64_t get_monotonic_time() {
	struct timespec timespec;
	clock_gettime(CLOCK_MONOTONIC, &timespec);
	return timespec.tv_sec * 1000 * 1000 * 1000 + timespec.tv_nsec;
}

void check_interrupt(struct interrupts* interrupts, uint64_t time) {
    interrupts->interrupt_enabled = pps(interrupts->rx_pkts, time - interrupts->last_time_checked) <= 10;
	interrupts->rx_pkts = 0;
	interrupts->last_time_checked = get_monotonic_time();
}