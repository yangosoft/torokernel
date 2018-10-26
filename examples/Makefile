
all: hello.o

%.o: %.c
	gcc -nostdlib -c $< -o $@
	

clean:
	rm -f hello.o
