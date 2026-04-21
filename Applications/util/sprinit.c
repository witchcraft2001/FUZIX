#include <unistd.h>
#include <fcntl.h>

int main(int argc, char *argv[])
{
	int fdtty1;
	static const char msg[] = "SPRINTER WRITE OK\r\n";

	argc = argc;
	argv = argv;
	getpid();
	do {
		fdtty1 = open("/dev/tty1", O_RDWR | O_NOCTTY);
	} while (fdtty1 < 0);
	dup(fdtty1);
	dup(fdtty1);
	write(1, msg, sizeof(msg) - 1);

	for (;;) {
		pause();
	}
}
