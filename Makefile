gmni/gmni: gmni/.build/config.mk
	cd gmni; make

gmni/configure:
	git submodule update --init

gmni/.build/config.mk: gmni/configure
	cd gmni; ./configure
