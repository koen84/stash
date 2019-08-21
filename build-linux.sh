#!/usr/bin/env bash
set -ex

# test distro versions
centos="7"
ubuntu="18.04"
debian="10"

# gather system information
if [ -f "/etc/os-release" ]; then
	distro=$(cat /etc/os-release | grep ^ID= | sed -e "s/^ID=//" | sed -e 's/"//g' | sed -e "s/'//g")
	distrov=$(cat /etc/os-release | grep ^VERSION_ID= | sed -e "s/^VERSION_ID=//" | sed -e 's/"//g' | sed -e "s/'//g")
elif [ -f "/etc/system-release" ]; then
	distro=$(cat /etc/system-release | awk '{print tolower($1)}')
	distrov=$(cat /etc/system-release | awk '{print $3}')
fi

echo "Running on $distro $distrov"

if [ $(id -u) == 0 ]; then
	_sudo=""
else
	_sudo="sudo"
fi

# function to install necessary packages with yum, after verifying root privileges
with_yum(){
	if [ $(id -u) == 0 ] || ( [ -n "$(which sudo)" ] && [ -n "$(groups | grep wheel)" ] ); then
	        echo "Installing dependencies using yum."
		$_sudo yum -y install gcc gcc-c++ make libtool automake pkgconfig openssl-devel libevent-devel curl bzip2 patch
	else
		echo -e "ERROR : script must be run as root.  Otherwise install sudo and have sudo rights on your account.\nHINT : yum install sudo"
		exit 1
	fi
}

# function to install necessary packages with apt-get, after verifying root privileges
with_apt(){
	if [ $(id -u) == 0 ] || ( [ -n "$(which sudo)" ] && [ -n "$(groups | grep sudo)" ] ); then
	        echo "Installing dependencies using apt-get."
		$_sudo apt-get -y install build-essential libtool autotools-dev automake pkg-config libssl-dev libevent-dev bsdmainutils curl
	else
		echo -e "ERROR : script must be run as root.  Otherwise install sudo and have sudo rights on your account.\nHINT : apt-get install sudo"
		exit 1
        fi
}

# function using yum, to fix out of date packages
# put the files outside of the stash git directory
yum_outofdate(){
	cd ..
	$_sudo curl https://people.centos.org/tru/devtools-2/devtools-2.repo -o /etc/yum.repos.d/devtools-2.repo
	$_sudo yum -y install git autoconf centos-release-scl devtoolset-2-gcc devtoolset-2-binutils devtoolset-2-gcc-c++

# needs heredoc or otherwise drops into rootshell and halt script
$_sudo /bin/bash <<EOF
	scl enable devtoolset-2 bash
EOF

	curl http://ftp.gnu.org/gnu/autoconf/autoconf-2.69.tar.gz | tar -xz
	pushd autoconf-2.69
	./configure
	make
	$_sudo make install
	popd
	rm -rf autoconf-2.69*
	cd stash
	grep -qxF 'm4_pattern_allow(PKG_CONFIG_LIBDIR)' configure.ac || echo 'm4_pattern_allow(PKG_CONFIG_LIBDIR)' >> configure.ac
}

# logic to select package installer
# displays warning if not used on a tested version of the distro
# allows to select yum or apt when distro is not explicitly supported
case $distro in
        centos)
#		if [ -z "$distrov" ]; then distrov=$(rpm -E %{rhel}); fi

		case $distrov in
			6*)
				with_yum
				yum_outofdate
				;;
			7)

				with_yum
				;;
			*)
				echo "WARNING : this script has not been tested on version $distrov of $distro.  Continuing to run."
		                with_yum
				;;
		esac
                ;;

        ubuntu)
                if [[ "$distrov" != "$ubuntu" ]]; then echo "WARNING : this script has not been tested on version $distrov of $distro.  Continuing to run."; fi
                with_apt
                ;;

        debian)
                if [[ "$distrov" != "$debian" ]]; then echo "WARNING : this script has not been tested on version $distrov of $distro.  Continuing to run."; fi
                with_apt
                ;;

        *)
                echo "ERROR : $distro is not supported by this script. To try continue anyway, type yum or apt to use as package manager.  Anything else will abort the script."
                read installer

                case $installer in
                        yum)
                                with_yum
                                ;;
                        apt)
                                with_apt
                                ;;
                        *)
                                echo "Exiting script now."
                                exit
                                ;;
                esac
		;;
esac

cores=$(nproc)
VERSION=$( cat ./src/clientversion.h | grep -m4 "#define CLIENT_VERSION" | awk '{ print $NF }' | tr '\n' '.' )
VERSION=${VERSION::-1}

HOST="x86_64-linux-gnu"
#HOST="$(./depends/config.guess)"
PREFIX="$(pwd)/depends/$HOST/"

cd depends/ && make -j$cores V=1 HOST=$HOST "$@" && cd ../
./autogen.sh
./configure  --prefix="${PREFIX}" --disable-ccache \
                                  --disable-maintainer-mode \
                                  --disable-dependency-tracking \
                                  --enable-glibc-back-compat \
                                  --enable-reduce-exports \
                                  --disable-bench \
                                  --disable-tests \
                                  --disable-gui-tests
                                 
make -j$cores V=1 "$@"

# Make the release

DIST="release/stashcore-${VERSION}-${HOST}"
CHECKSUM="SHA256SUMS"

# pre-clean up
rm -r ${DIST} || true
mkdir -p ${DIST}/{bin,utils}

# Create tar.gz
cp ./src/stashd ${DIST}/bin
cp ./src/stash-cli ${DIST}/bin
cp ./src/stash-tx ${DIST}/bin
cp ./src/qt/stash-qt ${DIST}/bin
cp ./zcutil/fetch-params.sh ${DIST}/utils
pushd ${DIST}/bin

# create checksums
sha256sum stashd > ${CHECKSUM}
sha256sum stash-cli >> ${CHECKSUM}
sha256sum stash-tx >> ${CHECKSUM}
sha256sum stash-qt >> ${CHECKSUM}
gpg --clearsign ${CHECKSUM} && rm -r ${CHECKSUM} || true
popd

# create tar.gz
#pushd release && find stashcore-${VERSION}-${HOST} -not -name "*.dbg" | sort | tar --no-recursion --mode='u+rw,go+r-w,a+X' --owner=0 --group=0 -c -T - | gzip -9n > stashcore-${VERSION}-${HOST}.tar.gz
#echo $( sha256sum stashcore-${VERSION}-${HOST}.tar.gz ) >> ${CHECKSUM}
pushd release && find stashcore-${VERSION}-${HOST} -not -name "*.dbg" | sort | tar --no-recursion --mode='u+rw,go+r-w,a+X' --owner=0 --group=0 -c -T - | gzip -9n > stashcore-${VERSION}-${HOST}-${distro}${distrov}.tar.gz
echo $( sha256sum stashcore-${VERSION}-${HOST}-${distro}${distrov}.tar.gz ) >> ${CHECKSUM}
popd
rm -r ${DIST} || true
