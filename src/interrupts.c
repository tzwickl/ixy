#include "interrupts.h"
#include "libixy-vfio.h"

#include <stdio.h>

/**
 * Calculate packets per second based on the received number of packets and the elapsed time in nanoseconds since the
 * last calculation.
 * @param received_pkts Number of received packets.
 * @param elapsed_time_nanos Time elapsed in nanoseconds since the last calculation.
 * @return Packets per second.
 */
static double pps(uint64_t received_pkts, uint64_t elapsed_time_nanos) {
	return (double) received_pkts / ((double) elapsed_time_nanos / 1000000000.0);
}

/**
 * Get current timestamp in nanoseconds based on rdtsc.
 */
uint64_t get_monotonic_time() {
	struct timespec timespec;
	clock_gettime(CLOCK_MONOTONIC, &timespec);
	return timespec.tv_sec * 1000 * 1000 * 1000 + timespec.tv_nsec;
}

/**
 * Check if interrupts or polling should be used based on the current number of received packets per seconds.
 * @param interrupts The interrupt handler.
 * @param time The current time in nanoseconds.
 */
void check_interrupt(struct interrupts* interrupts, uint64_t time) {
    interrupts->interrupt_enabled = pps(interrupts->rx_pkts, time - interrupts->last_time_checked) <= 10;
	interrupts->rx_pkts = 0;
	interrupts->last_time_checked = get_monotonic_time();
}