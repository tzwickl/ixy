#ifndef IXY_INTERRUPTS_H
#define IXY_INTERRUPTS_H

#include <stdint.h>
#include <stddef.h>
#include <time.h>
#include <stdbool.h>

#define MOVING_AVERAGE_RANGE 5
#define INTERRUPT_THRESHOLD 1.2

struct interrupt_moving_avg {
	uint32_t index;
	uint32_t length;
	double sum;
	double measured_rates[MOVING_AVERAGE_RANGE];
};

struct interrupt_queues {
	int vfio_event_fd; // event fd
	int vfio_epoll_fd; // epoll fd
	bool interrupt_enabled;
	uint64_t last_time_checked;
	uint64_t rx_pkts;
	uint64_t interval;
	struct interrupt_moving_avg moving_avg;
};

struct interrupts {
	bool interrupts_enabled; // Whether interrupts for this device are enabled or disabled.
	uint32_t itr_rate; // The Interrupt Throttling Rate
	struct interrupt_queues *queues; // Interrupt settings per queue
	int interrupt_type; // MSI or MSIX
	int timeout_ms; // interrupt timeout in milliseconds (-1 to disable the timeout)
};

void check_interrupt(struct interrupt_queues* interrupt, uint64_t diff, uint32_t buf_index, uint32_t buf_size);

#endif //IXY_INTERRUPTS_H
