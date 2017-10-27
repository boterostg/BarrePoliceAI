set -e
printf "This script is intended to work with Debian GNU/Linux 8, other versions may also\n"
printf "work. Root access is required to complete the installation. Press enter to continue,\n"
printf "or press CTRL + C to abort.\n"
read
sudo apt-get update
sudo apt-get install -y\
	git \
	wget \
	openssl \
	coreutils \
	make \
	gcc \
	libreadline-dev \
	libssl-dev \
	unzip \
	libexpat1-dev \
	libcurl3 \
	libcurl3-gnutls \
	libcurl4-openssl-dev \
	lua5.3 \
	luarocks
printf "[Info] Installing openssl...\n"
sudo luarocks install --server=http://luarocks.org/dev openssl
rocklist="luasocket luasec multipart-post lpeg dkjson serpent luafilesystem luaossl telegram-bot-lua luacrypto lua-openssl"
for rock in $rocklist
do
    printf "[Info] Installing $rock...\n"
    sudo luarocks install $rock
done
sudo -K
printf "[Info] Installation complete.\n"
