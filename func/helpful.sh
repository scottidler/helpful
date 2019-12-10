#!/bin/bash

if [ -n "$DEBUG" ]; then
    PS4=':${LINENO}+'
    set -x
fi

function vim() {
	ARGS=("$@")
	VIM=/usr/bin/vim

	VIM_MIN="${VIM_MIN:-2}"
	VIM_MAX="${VIM_MAX:-3}"

	for arg in "${ARGS[@]}"; do
		if [[ "$arg" == "-"* ]]; then
			eval $VIM "${ARGS[@]}"
		fi
	done

	case ${#ARGS[@]} in
		[0-1])                  eval $VIM    "${ARGS[@]}";;
		[$VIM_MIN-$VIM_MAX])    eval $VIM -O "${ARGS[@]}";;
		*)                      eval $VIM -o "${ARGS[@]}";;
	esac
}

function vim755() {
    vim "$@"
    chmod 755 "$@"
}

function touch755() {
    touch "$@"
    chmod 755 "$@"
}

function follow() {
	FILE="$1"
	printf $FILE
	while true; do
		FILE=`readlink $FILE`
		if [ -z "$FILE" ]; then
			break
		fi
		printf " -> $FILE"
	done
	echo
}

function mine() {
	sudo chown -R $USER:$USER "$@"
}

function mkfiles() {
	NUM="$1"
	DIR="${2:-.}"

	echo "NUM=$NUM"
	echo "DIR=$DIR"

	if ((NUM > 0)); then
		mkdir -p $DIR
		for i in `seq 1 $NUM`; do
			mktemp -p $DIR
		done
	else
		echo "NUM [DIR]"
		return 1
	fi
}

function ls-docker-tags() {
	if [ "$#" -ne 1 ]; then
		echo "supply image name"
		return 1
	fi
	wget -q https://registry.hub.docker.com/v1/repositories/$1/tags -O -  | sed -e 's/[][]//g' -e 's/"//g' -e 's/ //g' | tr '}' '\n'  | awk -F: '{print $3}'

}

function dhclient-restart() {
	ETHDEV=${1:-$(ip route get 1.1.1.1 | grep -Po '(?<=dev\s)\w+' | cut -f1 -d ' ')}
	sudo dhclient -r -v $ETHDEV && sudo rm /var/lib/dhcp/dhclient.*; sudo dhclient -v $ETHDEV
}

function pmu() {
	if hash apt-get 2> /dev/null; then
		echo "updating apt packages..."
		sudo apt-get update
		sudo apt-get upgrade -y --allow-unauthenticated --allow-downgrades
		sudo apt-get dist-upgrade -y
		sudo apt-get autoremove -y
	fi
	if hash dnf 2> /dev/null; then
		echo "updating dnf packages..."
		sudo dnf upgrade -y
	elif hash yum 2> /dev/null; then
		echo "updating yum packages..."
		sudo yum upgrade -y
	fi
}

function piu2() {
	if hash pip2 2> /dev/null; then
		echo "updating pip2 packages..."
		PKGS="`pip2 list | tail -n +3 | cut -d' ' -f1 | xargs echo -n`"
		sudo -H python2 -m pip install --upgrade $PKGS
	fi
}

function piu3() {
	if hash pip3 2> /dev/null; then
		echo "updating pip3 packages..."
		PKGS="`pip3 list | tail -n +3 | cut -d' ' -f1 | xargs echo -n`"
		sudo -H python3 -m pip install --upgrade $PKGS
	fi
}

function update() {
	set -e
	echo
	pmu
	echo
	piu3
}

function reboot() {
	kill-chrome
	kill-firefox
	sudo systemctl reboot
}

function nightly() {
	URLS=""
	for ARG in "$@"; do
		if [ -f "$ARG" ]; then
			URLS+="$(cat "$ARG" | xargs echo -n) "
		else
			URLS+="$ARG "
		fi
	done
	firefox-trunk -private "$URLS"
}

function replace() {
	FIND="$1"
	REPL="$2"
	DIR="${3-.}"
	if [ -z "$FIND" ]; then
		echo "replace FIND [REPL] [DIR]"
		return 1
	fi
	find "$DIR" -path ./.git -prune -o -type f -exec sed -i "s/$FIND/$REPL/g" {} \;
}

function ovpn() {
	ARGS="$@"
	sudo pkill openvpn
	find ~/.openvpn/ -name *.ovpn |
	while read FILEPATH; do
		DIR=`dirname $FILEPATH`
		CFG=`basename $FILEPATH`
		CMD="(cd $DIR && sudo openvpn --config $CFG $ARGS) &"
		echo "$CMD"
		eval "$CMD"
	done
}
