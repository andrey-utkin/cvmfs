#include <assert.h>
#include <sys/types.h>
#include <dirent.h>
#include <unistd.h>
#include <limits.h>
#include <stdio.h>
#include <stdbool.h>
#include <errno.h>

int main(int argc, char *argv[]) {
	assert(argc == 2);
	DIR *dir = opendir(argv[1]);
	if (!dir)
		return errno;

	struct dirent *entry;
	unsigned int count = 0;
	while ((entry = readdir(dir)) != NULL) {
	    count++;
	}
	printf("opened, read %u dirent\n", count);

	fflush(stdout);
	while (true) {
		sleep(INT_MAX);
	}
	return 0;
}
