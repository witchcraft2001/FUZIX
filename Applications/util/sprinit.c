#include <unistd.h>

static volatile unsigned char spin;

int main(int argc, char *argv[])
{
	static const char msg[] = "SPRINTER WRITE ONLY OK\r\n";

	argc = argc;
	argv = argv;
	write(1, msg, sizeof(msg) - 1);

	for (;;) {
		spin++;
	}
}
